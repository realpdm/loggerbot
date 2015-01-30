#!/usr/bin/env ruby

require 'rubygems'
require 'bundler/setup'
require 'cinch'
require 'pp'
require 'time'
require "yaml"
require 'sqlite3'
require_relative "channellogger.rb"
require 'tzinfo'


class Logger
  include Cinch::Plugin
  
  listen_to :connect,   method: :logger_connect
  listen_to :invite,    method: :logger_invite
  #match(/Channel (#.+) created by (.+)!/, react_on: :notice, method: :channel_created)
  #match(/.*/, react_on: :notice, method: :channel_created)
  
  match "help",        method: :logger_help
  match "leave",        method: :logger_leave
  match "url",          method: :url
  match /chime\s?(.*)?/, method: :logger_chime
  listen_to :message,  method: :on_message
  listen_to :join, method: :on_join
  listen_to :part, method: :on_part
  listen_to :topic, method: :on_topic
  listen_to :notice, method: :channel_created
  timer 30, method: :leave_empty_channel
  timer 60, method: :check_url_changed


  def logger_connect(m)
    
    bot.irc.send("oper logger #{config[:oper_password]}")
    bot.irc.send("mode logger +s +j")
    @channel_log = ChannelLogger.new ( {
         :logdir => config[:logdir],
         :baseurl => config[:baseurl]
      }
    )
    @db = SQLite3::Database.new(config[:db_path])
    @last_chime = Hash.new
    @urls = Hash.new
  end  
  
  def logger_invite(m)
    logger_join(m.channel.name)
    if in_db?(m.channel.name)
       info("#{m.channel.name} is in the db")
       set_autojoin(m.channel.name, :on)
    else
       debug("#{m.channel.name} is NOT in the db, adding it")
       @db.execute("insert into logger values ('#{m.channel.name}','1','1','','')")
    end
        
  end
 
 
 

  def on_message(m)
     return if m.channel.nil? || m.user.nil?
     logger_message(m.channel.name, m.user.nick, m.params[1])
  end
 
   def on_join(m)
      logger_message(m.channel.name, m.user.nick, " joined channel")
   end
   
   def on_part(m)
      logger_message(m.channel.name, m.user.nick, " left the channel")
      leave_empty_channel
      
   end
   def on_topic(m)
      logger_message(m.channel.name, m.user.nick, " set topic to: #{m.params[1]}")
      
   end
   
  
  def logger_message(channel, nick, text)
     @channel_log.log(channel, nick, text)  
     now =  Time.now.to_i
     @last_chime[channel]=now  unless @last_chime.has_key?(channel)
     
     if ( now - @last_chime[channel] >= 3600 ) || (now ==  @last_chime[channel] )
        emit_chime(channel) if chime?(channel) == :on 
        @last_chime[channel]=now
     end   
              
  end
  
  def channel_created(m)
    m.params[1] =~ /Channel (#.+) created by/
    channel = $1
    return if channel.nil?
    if autojoin?(channel)
       info "%s was set for auto join" % [channel]
       Channel(channel).join
    else
       config[:autojoin].each do |pattern|
          re = Regexp.new(pattern)
          if re.match(channel)
             Channel(channel).join 
             info("auto joining #{channel}")
          else
             info "pattern %s with regex %s did not match '%s'" % [pattern, re.to_s, channel]
          end
       end

    end
  end
  
  def logger_initialize
     # I should auto join channels here, etc
     # 
  end
  
  def logger_join(channel)
     @channel_log.log(channel, "logger", "joined channel")
     Channel(channel).join
     leave_empty_channel
     
  end
  
  def logger_leave(m)
     @channel_log.log(m.channel.name, "logger", "left channel")
     Channel(m.channel.name).part
     set_autojoin(m.channel.name,:off)
     @channel_log.close_log(m.channel.name)
     
  end
 
  def url(m)
    m.reply "log file url is #{@channel_log.url(m.channel.name)}"
    @channel_log.log(m.channel.name, "logger", "log file url is #{@channel_log.url(m.channel.name)}")
    
  end
 
 def check_url_changed
    bot.channels.each do |channel|
      newurl = @channel_log.url(channel.name)
      if (newurl != @urls[channel.name])
         @urls[channel.name] = newurl
         Channel(channel).send("log file url is now #{newurl}")
         @channel_log.log(channel.name, "logger", "log file url is now #{newurl}")
         
      end
    end
    
 end
 
  def logger_chime(m, state)
      debug("in logger_chime channel is #{m.channel.name}")
      debug("state is '#{state}'")
      pp state.class
      if state.empty?
         m.reply("Current hourly chime is: #{chime?(m.channel.name)}") 
         return
      end
      case state
      when "on"
         set_chime(m.channel.name, :on)
         m.reply "hourly chime is now on"
      when "off"
         set_chime(m.channel.name, :off)
         m.reply "hourly chime is now off"
      else 
         m.reply "chime state can be 'on' or 'off'"
      end
  end

  def logger_help(m)
	m.reply("Commands: 'leave' leave channel and remove auto join; 'url' show current log url; 'chime, chime (on|off)' Show hourly chime state or set it on/off; ")
  end

 
  def chime?(channel)
     debug "inside chime? channel is #{channel}"
     chime_state = @db.get_first_row("select chime from logger where channel=='#{channel}'")
     return :on if chime_state[0] == 1
     return :off

  end
  
  
  def set_chime(channel,newstate="") 
     case newstate
     when :on
        @db.execute("update logger set chime='1' where channel=='#{channel}'")
     when :off
        @db.execute("update logger set chime='0' where channel=='#{channel}'")            
     end
  end
  
  def hourly_chime
     bot.channels.each do |channel|
        debug ("checking hourly chime for #{channel}\n")
        Channel(channel).send "log file url is #{@channel_log.url(channel.to_s)}" if chime?(channel.to_s) == :on
     end
      
  end
  
  def emit_chime(channel)
     # time is 2009-08-10 00:00 PDT; 03:00 EDT; 07:00 GMT; 12:30 IST; 15:00 CST
     # time is 2010-04-10 07:00 PDT; 10:00 EDT; 14:00 GMT; 19:30 IST; 22:00 CST
     # time is 2010-03-01 18:00 PST; 21:00 EST; 2010-03-02 02:00 GMT; 07:30 IST; 10:00 CST
     
     chime_string = "time is "
     
     time_zones = Hash[ :Austin => "US/Central", 
         :UTC => "UTC", 
         :London => "Europe/London", 
         :Paris => "Europe/Paris"
      ]
      
      prev_date = ""
      current_index = 1
      time_zones.each_key do |zone|
        tz = TZInfo::Timezone.get(time_zones[zone])
        tz_time =  tz.strftime("%R")
        tz_date =  tz.strftime("%F")
        chime_string << tz_date << " " unless  tz_date == prev_date
        chime_string << tz_time << " " << zone.to_s 
        chime_string << "; " unless current_index >= time_zones.length
        prev_date = tz_date
        current_index+=1
      end

      Channel(channel).send chime_string
      @channel_log.log(channel, "logger", chime_string)
      
  end
  
  def autojoin?(channel)
     autojoin_state = @db.get_first_row("select autojoin from logger where channel=='#{channel}'")
     return false if autojoin_state.nil?
     return true if autojoin_state[0] == 1
     return false

  end
  
  
  def set_autojoin(channel,newstate="") 
     case newstate
     when :on
        @db.execute("update logger set autojoin='1' where channel=='#{channel}'")
     when :off
        @db.execute("update logger set autojoin='0' where channel=='#{channel}'")            
     end
  end
  
  
  def in_db?(channel)
     channel_db = @db.get_first_row("select channel from logger where channel=='#{channel}'")
     return false if channel_db.nil? 
     channel_db[0] == channel
     
  end
  
  def leave_empty_channel
     bot.channels.each do |channel|
        #print "Channel: %s  Users: %s" % [channel, channel.users.size]
        if channel.users.size == 1
           @channel_log.log(channel.name, "logger", "leaving empty channel")
           Channel(channel.name).part
           @channel_log.close_log(channel.name)
        end
     end
  end
end

