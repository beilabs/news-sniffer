#    News Sniffer
#    Copyright (C) 2007-2008 John Leach
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU Affero General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU Affero General Public License for more details.
#
#    You should have received a copy of the GNU Affero General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

#
class NewsArticlesController < ApplicationController
  layout 'newsniffer'

  def index
    @title = "Latest news articles"
    @articles = NewsArticle.paginate :include => 'versions', :page => params[:page] || 1,
      :order => "news_articles.id desc", :per_page => 20
  end

  def show
    @article = NewsArticle.find(params[:id])
    @versions = @article.versions.all(:order => 'version asc', :select => "id, version, title, created_at")
    respond_to do |format|
      format.html
      format.rss { render :content_type => 'application/rss+xml', :layout => false }
    end
  end

end
