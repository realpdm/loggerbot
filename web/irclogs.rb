#!/usr/local/bin/ruby
# encoding: utf-8
require 'rubygems'
require 'bundler/setup'
require 'cgi'
require 'erb'
require 'cgi_exception'
require 'pp'
require 'date'

Encoding.default_external = "UTF-8"


print "Content-type: text/html\n\n"


LOG_BASE_DIR = "/home/irc/irclogs";


def make_url(channel,date)
   "https://#{ENV["HTTP_HOST"]}/irclogs/#{channel}/#{(date).to_s}.txt"
end

def make_file_path(channel,date)
   "#{LOG_BASE_DIR}/#{channel}/#{date.year}/#{date.strftime('%m')}/#{date}.txt"

end


cgi = CGI.new
erb = ERB.new(File.read("template.html"))

date = Date.parse(cgi.params['log'][0])
channel = cgi.params['channel'][0]


hilight = cgi.params['hilight'][0]
grep = cgi.params['grep'][0]


unless File.exists?(make_file_path(channel,date))
   raise ("No channel log exists for that date")
end

begin
   logfile = File.open(make_file_path(channel,date),"r:utf-8")
rescue Exception => e
   raise "Failed to open: #{e}"
end

output = String.new
logfile.each_line do |line|
   next if  grep &&  line !~ /#{grep}/
   
   line = line.gsub(/(#{hilight})/, "<b class='hilight'>\\1</b>") unless hilight.nil?
   output << "<div class='logline''>"
   output << line 
   output << "</div>\n"
   
end

previous_link = "<a href='#{make_url(channel,date-1)}'>&larr; #{date-1}</a>" if File.exists?(make_file_path(channel,date-1))
next_link = "<a href='#{make_url(channel,date+1)}'>#{date+1} &rarr;</a>" if File.exists?(make_file_path(channel,date+1))

IRCLOG = { :title => "##{channel} log #{date}",
            :previous => previous_link,
            :next => next_link,
            :log => output,
            :grep => grep,
            :hilight => hilight,
            
   }

html = erb.result
cgi.print html

