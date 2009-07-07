#! /usr/bin/env ruby
require 'csv'

ARGV = ['House.S05E16.new.txt', '41.70833333118505']

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
  die "usage: ruby #{File.basename(__FILE__)} input_file framerate" if ARGV.size < 2
  
  input_file  = ARGV[0]
  frame_rate  = ARGV[1].to_f

  File.file? input_file  or die "input file not found: #{input_file}"
  
  tracks = {}
  
  CSV.parse(File.read(input_file).gsub('; ', ';'), ?;) do |row|
    next if row[1] =~ /Track/
    track      = row[1]
    start_time = row[2].to_f
    length     = row[3].to_f
    file_name  = row[11]
    
    track = (tracks[track] ||= Track.new(file_name))
    track.add_range! start_time, length
  end
  
  max_end_time = tracks.values.collect { |t| t.previous_end_time }.max
  tracks.values.each { |t| t.add_range! max_end_time, 0.0 }
  
  tracks.values.each { |t| puts "** #{t.file_name}"; t.skipped_ranges.collect { |r| "#{r[0]*frame_rate/100}--#{r[1]*frame_rate/100}"}.each { |s| puts s } }

end
