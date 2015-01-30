#!/usr/local/bin/ruby

require 'rubygems'
require 'bundler/setup'
require 'cinch'
require 'pp'
require 'time'
require "yaml"
require 'sqlite3'
require_relative "channellogger.rb"
require_relative "logger.rb"


config = YAML::load(File.open("logger.yml"))

autojoin_channels = Array.new
db = SQLite3::Database.new(config["db_path"] )
db.execute( "select channel from logger where autojoin=='1'")  do |row|
   autojoin_channels.push row[0]
end
   

bot = Cinch::Bot.new do
  configure do |c|
    c.server   = config["server"]
    c.channels = autojoin_channels
    c.nick = config["nickname"]
    c.password = config["password"]
    c.realname = config["realname"]
    c.user = config["user"]
    c.port = config["port"]
    c.ssl.use = config["ssl"]    
    c.plugins.plugins = [Logger]
    c.plugins.prefix = /^#{config['nickname']} /
    
    c.plugins.options[Logger] = {
       :db_path => config["db_path"],
       :oper_password => config["oper_password"],
       :logdir => config["logdir"],
       :baseurl => config["baseurl"],
       :autojoin => config["auto_join_patterns"],
      }
  end

end
#    c.plugins.prefix = /^#{config["nick"]} /

bot.loggers.level = :info
bot.loggers.first.level  = :info
bot.start
