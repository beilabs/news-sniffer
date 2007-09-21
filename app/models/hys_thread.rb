# The HysThread model represents a BBC Have Your Say thread.
# The +++censored+++ relation returns all associated HysComments that were censored.
# The +++hardcensored+++ relation returns all associated HysComments that have remained censored for
# a period of time.
class HysThread < ActiveRecord::Base
  attr_accessor :ccount
  attr_reader :oldest_rss_comment
  has_many :hys_comments
  validates_uniqueness_of :bbcid
  validates_presence_of :title
  has_many :censored, :class_name => 'HysComment', :conditions => ["censored = #{CENSORED}"]
  has_many :published, :class_name => 'HysComment', :conditions => ["censored = #{NOTCENSORED}"]
  
  @@comments_rss_url = "http://newsforums.bbc.co.uk/nol/rss/rssmessages.jspa?threadID=%s&lang=en&numItems=400"
  @@thread_rss_url = "http://newsrss.bbc.co.uk/rss/newsonline_uk_edition/talking_point/rss.xml"

  # Return the url to the bbc website for this thread
  def url
    "http://newsforums.bbc.co.uk/nol/thread.jspa?threadID=#{bbcid}"
  end

  # Return nill if bbcid isn't in database
  def self.bbcid_exists?(bbcid)
    self.connection.execute("select bbcid from hys_threads where bbcid = #{bbcid.to_i}").fetch_row
  end

  # return a list of HysComment objects instantiated from the RSS feed for this thread
  def find_comments_from_rss(force = false)
      HysThread.benchmark("BENCHMARK:find_comments_from_rss: download and parse rss feed", use_silence = false) do
      # Download and parse RSS feed.  Return nil if the feed it broken or stale
      rssurl = @@comments_rss_url.gsub('%s', self.bbcid.to_s) + "&random=#{rand(999999)}"
      logger.debug "DEBUG:hysthread:#{self.bbcid} title: '#{self.title}'"
                       rssdata = nil
      newsize = HTTP::remote_filesize(rssurl)
			if newsize
				logger.debug "DEBUG:hysthread:#{self.bbcid} - content-length header exists"
			else	
	      begin
	        rssdata = HTTP::zget(rssurl)
	      rescue OpenURI::HTTPError => e
					logger.error("ERROR:hysthread:#{self.bbcid}: #{e.to_s}")
          return nil
	      end
      	newsize = rssdata.size
			end
      lastsize = self.rsssize
      if lastsize.to_i == newsize.to_i and force == false
        logger.debug "DEBUG:hysthread:#{self.bbcid} - no change in comments rss"
        return nil
      end
			logger.info("INFO:hysthread:#{self.bbcid} - comments rss updated - #{self.title}")
      self.rsssize = newsize
			rssdata = HTTP::zget(rssurl) if rssdata.nil?
      begin
          @rss = SimpleRSS.parse rssdata
      rescue SimpleRSSError => e
					logger.error("ERROR:hysthread:#{self.bbcid} - error parsing comments rss: #{e.to_s}")
          return nil
      end
      if !self.last_rss_pubdate.nil? and @rss.lastBuildDate < self.last_rss_pubdate and force == false
        logger.info("INFO:hysthread:#{self.bbcid} - rss pubDate older than last time, ignoring (#{@rss.lastBuildDate} < #{self.last_rss_pubdate})")
        return nil
      end
      self.last_rss_pubdate = @rss.lastBuildDate
      self.save
      end # benchmark
      
      # RSS is not broken or stale, so...
      
      # Build HysComment object for all entires in the RSS feed and create any comments not already in the database
      HysThread.benchmark("BENCHMARK:find_comments_from_rss: create any new comments from feed", use_silence = false) do
      new_count = 0
      @rsscomments = []
      @rss.entries.each do |e|
        c = HysComment.instantiate_from_rss(e, self.id)
        if c.nil?
          logger.debug("DEBUG:HysComment.instantiate_from_rss returned nil")      
          next 
        end
        logger.debug("DEBUG:HysComment: #{c.bbcid}")
        next if @rsscomments.include?(c) # The BBC feeds include duplicates, duh.  we ignore them
        logger.debug("DEBUG:HysComment not in @rsscomments")
        
        # Create this comment if it's not already in the database
        unless self.comments_ids.include?(c.bbcid)
          logger.debug("DEBUG:HysComment.bbcid not in comments_ids")
          new_count += 1
          c.hys_thread = self
          c.save
          logger.info("INFO:hysthread:#{self.bbcid} new comment #{c.bbcid} created at #{c.created_at} by #{c.author}")
          @comments_ids << c.bbcid
        end
        @rsscomments << c
      end
      logger.info "INFO:hysthread:#{self.bbcid} - #{new_count} new comments" if new_count > 0
      end # benchmark
      
      # Work out the date of the oldest comment in the feed.  Feeds are not sorted
      @oldest_rss_comment = Time.now
      @rsscomments.each do |c|

      @oldest_rss_comment = c.modified_at if c.modified_at < @oldest_rss_comment
      end

      return @rsscomments
  end

  # Find new threads from rss feed and create them
  #
  def self.find_from_rss
    benchmark("BENCHMARK:find_from_rss", use_silence = false) do
      rssdata = HTTP::zget(@@thread_rss_url)
      begin
        rss = SimpleRSS.parse rssdata
      rescue SimpleRSSError
          logger.error "ERROR:find_from_rss: error parsing thread list RSS"
          return nil
      end
      rss.entries.each do |e|
        begin
          rsslink = e[:link]
          bbcid = $1.to_i if rsslink =~ /^.*threadID=([0-9]+).*$/
          raise NameError, "couldn't get bbcid (threadID) from rsslink (#{rsslink})" if bbcid.nil?
          next if HysThread.bbcid_exists?(bbcid)
          t = HysThread.new
          t.title = e[:title]
          t.bbcid = bbcid
          t.created_at = Time.parse( e[:pubDate].to_s ).utc
          t.description = e[:description]
          t.save
        rescue NameError => e
          logger.error "ERROR:find_from_rss: RSS entry didn't look right: #{e.to_s}"
          next
        end
      end
    end
  end
  
  # Returns bbcids of all associated hys_comments
  def comments_ids
    return @comments_ids unless @comments_ids.nil?
    @comments_ids = []
    self.connection.execute("select bbcid from hys_comments where hys_thread_id = #{self.id}").each do |row|
      @comments_ids << row.first.to_i
    end
    @comments_ids
  end
  
  # Returns bbcids of all associated censored hys_comments
  def censored_comments_ids
    return @censored_comments_ids unless @censored_comments_ids.nil?
    @censored_comments_ids = []
    self.connection.execute("select bbcid from hys_comments where hys_thread_id = #{self.id} and censored = #{CENSORED}").each do |row|
      @censored_comments_ids << row.first.to_i
    end
    @censored_comments_ids
  end
  
  def <=>(other)
    self.bbcid <=> other.bbcid
  end

  # Scrape and return a list of comment ids for this thread from the BBC news website html
  def find_comments_ids_from_html
    @base_url = "http://newsforums.bbc.co.uk/nol/thread.jspa?threadID="

    @thread_id = 4221

    def thread_url_for(thread_id, page)
      @base_url + thread_id.to_s + "&start=" + page.to_s
    end

    @pages = [0]
    @ids = []

    @pages.each do |page|
      # download the page html
      html_url = "#{@base_url}#{self.bbcid}&start=#{page}"
      logger.info "INFO:HysThread.find_comments_ids_from_html: retrieving page #{page} at #{html_url}"
      html = HTTP::zget( html_url )
      if html.nil?
        logger.warn "WARN:HysThread.find_comments_ids_from_html: couldn't retrieve page #{page}"
        return nil
      end
      
      # Find any new pages in this page and add them to @pages
      new_pages = html.scan /thread.jspa\?.*;start=([0-9]+)/
      new_pages.each do |p|
        p = p.first.to_i 
        @pages << p unless @pages.include? p
      end
    
      # Find all the message ids in this page
      html.scan(/complaint!default.jspa\?messageID=([0-9]+)/).each do |id|
        id = id.first.to_i
        @ids << id unless @ids.include? id
      end
    end
    return @ids
  end

  # Return the first comment if it's the thread comment, describing the thread (usually is)
  def thread_comment
    @thread_comment = self.hys_comments.find(:first, :order => 'bbcid asc') unless @thread_comment
    return @thread_comment if @thread_comment and @thread_comment.author =~ /^(nol-j|BBC Host).*/
    nil
  end
  
  def censored_count 
    @censored_count ||= self.censored.count
  end
  
  def published_count 
    @published_count ||= self.published.count
  end
      
  def html_fixup
      html_ids = self.find_comments_ids_from_html
      if html_ids.nil?
        logger.warn("WARN:html_fixup found no comment ids from html for thread:#{self.bbcid}")
        return false
      end

      # Check for comments mark censored that are actually published
      mis_censored_ids = html_ids - (html_ids - self.censored_comments_ids)
      #if (html_ids - t.censored_comments_ids).size != html_ids.size
      if mis_censored_ids.size > 0
        logger.info("INFO:html_fixup found #{mis_censored_ids.size} published comments on bbc marked censored on newssniffer thread:#{self.bbcid}!")
        self.hys_comments.find_all_by_bbcid(mis_censored_ids).each { |c| c.uncensor! }
      end

      # Check for comments not mark censored that *are* actually censored
      mis_published_ids = (self.comments_ids - html_ids) - self.censored_comments_ids
      if mis_published_ids.size > 0
        logger.info("INFO:html_fixup found #{mis_published_ids.size} censored comments on bbc marked published on newssniffer thread:#{self.bbcid}!")
        self.hys_comments.find_all_by_bbcid(mis_published_ids).each { |c| c.censor! }
      end
  end
end
