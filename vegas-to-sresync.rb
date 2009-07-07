#! /usr/bin/env ruby
#
# == Synopsis
#
# vegas-to-sresync: converts Sony Vegas exported projects (in CSV) into srt-resync.rb input file format
#
# == Usage
#
# ruby vegas-to-sresync.rb [-f 24000/1001] exported_project.csv [track_1_name track_2_name ...]
#
# -f, --framerate:
#    override the default framerate of 24000/1001; acceptable formats are 123.45 and 987/654

require 'getoptlong'
require 'csv'
require 'rdoc/usage'

VEGAS_TO_SRESYNC_VERSION = '1.0'

def die s
  puts "Fatal error: #{s}"
  exit 1
end

class Track
  
  attr_reader :previous_end_time, :file_name, :skipped_ranges
  
  def initialize file_name
    @file_name = file_name
    @previous_end_time = 0.0
    @skipped_ranges = []
  end
  
  def add_range! start_time, length
    if start_time > @previous_end_time
      @skipped_ranges << [@previous_end_time, start_time]
    end
    @previous_end_time = start_time + length
  end
  
end

begin
  RDoc::usage if ARGV.size < 1

  opts = GetoptLong.new(
    [ '--framerate', '-f', GetoptLong::REQUIRED_ARGUMENT ]
  )
  frame_rate = '24000/1001'
  opts.each do |opt, arg|
    case opt
      when '--framerate'
        frame_rate = arg.strip
    end
  end
  
  input_file  = ARGV[0]
  subtitle_names = ARGV[1 .. -1]
  
  if frame_rate =~ %r!^(\d+)/(\d+)$!
    frame_rate_num = $1.to_i
    frame_rate_den = $2.to_i
  elsif frame_rate =~ /^([\d.]+)$/
    frame_rate_num = $1.to_f
    frame_rate_den = 1
  else
    die %Q,invalid frame rate format: "#{frame_rate}",
  end

  File.file? input_file  or die "input file not found: #{input_file}"
  
  tracks = {}
  
  CSV.parse(File.read(input_file).gsub('; ', ';'), ?;) do |row|
    next if row[1] =~ /Track/
    track      = row[1]
    start_time = row[2].to_f
    length     = row[3].to_f
    file_name  = File.basename(row[11].gsub('\\', '/'))
    
    track = (tracks[track] ||= Track.new(file_name))
    track.add_range! start_time, length
  end
  
  max_end_time = tracks.values.collect { |t| t.previous_end_time }.max
  tracks.values.each { |t| t.add_range! max_end_time, 0.0 }

  if subtitle_names.empty?
    common_prefix = 0; common_suffix = 0
    common_prefix += 1 while tracks.values.all? { |t| t.file_name[0 .. common_prefix].upcase == tracks.values.first.file_name[0 .. common_prefix].upcase }
    common_suffix += 1 while tracks.values.all? { |t| t.file_name[-common_suffix-1 .. -1].upcase == tracks.values.first.file_name[-common_suffix-1 .. -1].upcase }
    # puts tracks.values.first.file_name[0 .. common_prefix-1]
    # puts tracks.values.first.file_name[-common_suffix .. -1]
    # puts tracks.values.first.file_name[common_prefix .. -common_suffix-1]
  elsif subtitle_names.size != tracks.size
    puts "The number of subtitle track names specified (#{subtitle_names.size}) does not match the actual number of tracks (#{tracks.size}). Stop."
    exit 1
  end
  
  puts "#{frame_rate_num}/#{frame_rate_den}"
  puts
  tracks.values.each_with_index { |t, index| puts "#{if subtitle_names.empty? then t.file_name[common_prefix .. -common_suffix-1] else subtitle_names[index] end} " + t.skipped_ranges.collect { |r| [(r[0]*1.0*frame_rate_num/frame_rate_den/1000).round, (r[1]*1.0*frame_rate_num/frame_rate_den/1000).round] }.collect { |b,e| "#{b}+#{e-b}"}.join(", ") }

end
