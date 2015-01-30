require 'rubygems'
require 'bundler/setup'
require 'cinch'
require 'pp'
require 'time'
require "yaml"
require 'sqlite3'



class ChannelLogger

   def initialize (config="")
      @logdir = config[:logdir]
      @baseurl = config[:baseurl]
      #@logdir = "/Library/WebServer/Documents/irclogs"
      #@baseurl = "http://irc.wvrgroup.internal/irclogs/"
      @channel_logs = Hash.new
      @urls = Hash.new       
   end

   def log(channel,nick, line)     
     t = Time.new
     datestamp = t.strftime("%F")
     datedir = t.strftime("/%Y/%m")
     timestamp = t.strftime("%T")
     channel = clean(channel)
     channel_logdir = "#{@logdir}/#{channel}/#{datedir}"
     #@urls[channel] = "#{@baseurl}#{channel}/#{datedir}/#{datestamp}.txt"
     @urls[channel] = url(channel,t)
     FileUtils.mkdir_p(channel_logdir) unless File.directory?(channel_logdir)

     if @channel_logs.has_key?(channel)
        olddate = File.basename(@channel_logs[channel].path).sub("\.txt","")
        if datestamp != olddate 
           @channel_logs.delete(channel)
         end
     end
     
     unless @channel_logs.has_key?(channel)
        @channel_logs[channel] = File.new("#{channel_logdir}/#{datestamp}.txt", 'a')
        @channel_logs[channel].sync = true
     end      
     @channel_logs[channel].write("#{datestamp} #{timestamp} #{nick}: #{line}\n")
     
   end
   
   def close_log(channel)
      channel = clean(channel)
      @channel_logs[channel].close
      @channel_logs.delete(channel)
   end
      
   def url(channel,time=nil)
      time = Time.new if time.nil?
      datestamp = time.strftime("%F")
      datedir = time.strftime("/%Y/%m")
      channel = clean(channel)
      
      return "#{@baseurl}#{channel}/#{datestamp}.txt"
      
   end

   def clean(channel)
      channel.sub(/^#/, '')
   end
   
   
end
