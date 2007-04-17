#!/usr/bin/ruby

require File.dirname(__FILE__) + '/../../config/environment'
require 'drb'

module Ferret::Index
  class Index
    alias :real_search :search
  
    def search(*args)
      r = nil
      b = Benchmark.measure { r = real_search(*args) }
      q = args.first.is_a?(String) ? args.first : ""
      puts "ferret search for '#{q}' completed in#{b.to_s}"
      return r
    end
    
  end
end

class ActionController::Caching::Fragments::FileStore
  include DRb::DRbUndumped
  def write(*args)
    puts "fragment write " + args.first
    super *args
  end
  def read(*args)
    puts "fragment read " + args.first
    super *args
  end
  def delete(*args)
    puts "fragment delete " + args.first
    super *args
  end
  def delete_matched(*args)
    puts "fragment delete_matched " + args.first.to_s
    super *args
  end
end


puts "Starting druby ferret service on #{NsDrb::url}"
server = DRb::DRbServer.new(NsDrb::url, NsDrb::services, :verbose => true )
server.thread.join
