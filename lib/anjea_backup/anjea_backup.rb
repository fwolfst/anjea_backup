require 'date'
require 'fileutils'
require 'pathname'
require_relative 'inifile'

module AnjeaBackup
  class BackupItem
    attr_accessor :name
    attr_accessor :description
    attr_accessor :src_dir
    attr_accessor :ssh_url
    attr_accessor :ssh_key
  
    def initialize hash
      @name        = hash[:name]
      @description = hash['description']
      @src_dir     = hash['src']
      if hash['host'] && hash['user'] && hash['key']
        @ssh_url = "#{hash['user']}@#{hash['host']}:#{@src_dir}"
        @ssh_key = hash['key']
      end
    end
  end
  
  class Backup
    def initialize
      read_system_conf
      if !lock!
        log_err "Aborting, anjea already running.  Delete #{@lock_file} if not."
        exit 2
      end
      read_backups_conf
      setup_dirs
    end
  
    def backup
      yyyymmdd = DateTime.now.strftime("%Y-%m-%d-%H")
      
      # TODO work in a tmp work dir
      @backup_items.each do |item|
        last_backup  = File.join(@last, item.name)
        today_backup = create_now_backup_path(yyyymmdd, item)
        work_dir     = File.join(@partial, item.name, yyyymmdd)
        FileUtils.mkdir_p work_dir
  
        source = item.ssh_url ? "-e \"ssh -i #{item.ssh_key}\" #{item.ssh_url}"
                              : item.src_dir
  
        rsync_cmd = "rsync -avz --delete --relative --stats --log-file #{log_file_for(yyyymmdd, item)} --link-dest #{last_backup} #{source} #{today_backup}"
      
        log item, "rsync start"
        if system(rsync_cmd)
          log item, "rsync finished"
          # 'finish', move partial to backup-dest
          link_last_backup today_backup, last_backup
          log item, "linked"
        else
          # TODO Move this one into quarantaine/incomplete!
          log_err item, "rsync failed?"
        end
      end
      self
    end
  
    def cleanup
      now = DateTime.now
      @backup_items.each do |item|
        puts "[#{item.name}] backups:"
        puts "-- #{item.description} --"
        ages = Dir.glob("#{@destination}/[^c]*/#{item.name}").map do |dir|
          date_dir = Pathname.new(dir).parent.basename.to_s
          dtdiff = 0
          begin
            stamp = DateTime.strptime(date_dir, "%Y-%m-%d-%H")
            dtdiff = now - stamp
          rescue
            STDERR.puts "Do not understand timestamp in #{dir}"
          end
          [dtdiff, dir]
        end
        ages.sort.each do |age,dir|
          puts "(#{(age*24).to_i}) #{dir}"
        end
        puts
      end
    end
  
    def to_vault
    end
  
    private
  
    def setup_dirs
      Dir.mkdir @destination if !File.directory? @destination
      Dir.mkdir @vault       if !File.directory? @vault
      Dir.mkdir @log         if !File.directory? @log
      Dir.mkdir @last        if !File.directory? @last
      Dir.mkdir @partial     if !File.directory? @partial
      Dir.mkdir @failed      if !File.directory? @failed
    end
  
    def log_err item=nil, msg
      if item
        STDERR.puts "[#{item.name}] #{DateTime.now.strftime("%Y-%m-%d-%H:%M")} - #{msg}"
      else
        STDERR.puts "#{DateTime.now.strftime("%Y-%m-%d-%H:%M")} - #{msg}"
      end
    end
  
    def log item, msg
      puts "[#{item.name}] #{DateTime.now.strftime("%Y-%m-%d-%H-%M")} - #{msg}"
    end
  
    def lock!
      File.new(@lock_file,'w').flock( File::LOCK_NB | File::LOCK_EX )
    end
  
    def link_last_backup today_backup, last_backup
      FileUtils.rm_f last_backup
      FileUtils.ln_s(today_backup, last_backup, :force => true)
    end
  
    def read_backups_conf
      @backup_items = read_ini_file('backups.conf').map {|group| BackupItem.new group }
    end
  
    def read_system_conf
      system_conf = read_ini_file 'anjea.conf'
  
      @destination = system_conf[0]['dst']
      @vault       = system_conf[0]['vault']
      @log         = system_conf[0]['log']
      @last        = File.join(@destination, 'current')
      @failed      = File.join(@destination, 'failed')
      @partial     = File.join(@destination, 'partial')
      @lock_file   = system_conf[0]['lock']
    end
  
    def log_file_for yyyymmdd, item
      FileUtils.mkdir_p File.join(@log, item.name)
      File.join(@log, item.name, "#{yyyymmdd}.log")
    end
  
    def create_now_backup_path yyyymmdd, item
      today_backup = File.join(@destination, yyyymmdd, item.name)
      FileUtils.mkdir_p today_backup
      today_backup
    end
  
  end
end