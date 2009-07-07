#! /bin/env ruby
require 'fileutils'

$debug = false
if ARGV.include? '-d'
  ARGV -= ['-d']
  $debug = true
end

class IO
  def gets_skipping_emptylines_and_comments_and_strip
    while x = self.gets
      return x.strip unless x =~ /^\s*(#|$)/
    end
    return nil
  end
end

class File
  def self.open_or_stdin(file_name, &block)
    if file_name == '-'
      block.call($stdin)
    else
      File.open(file_name, &block)
    end
  end
end

class Fixnum
  
  def format_timestamp
    milli = self % 1000
    h = self / 1000
    s = h % 60
    h /= 60
    m = h % 60
    h /= 60
    sprintf("%02d:%02d:%02d,%03d", h, m, s, milli)    
  end
  
end

class TimeRange < Struct.new(:start, :end)
  
  def convert_to_time num, den
    TimeRange.new((self.start * 1000 * den / num + 0.5).to_i, 
                  (self.end   * 1000 * den / num + 0.5).to_i)
  end
  
  def to_s
    "[#{self.start}, #{self.end})"
  end
  
  def length
    self.end - self.start
  end
  
  def apply_operations(added_ranges, deleted_ranges)
    me = self
    added_ranges.each           do |range|
      $stdout.write "#{me} + #{range}" if $debug
      me = me.apply_addition(range)
      puts " = #{me}" if $debug
    end
    deleted_ranges.reverse.each do |range|
      $stdout.write "#{me} - #{range}" if $debug
      me = me.apply_deletion(range)
      puts " = #{me}" if $debug
    end
    return me
  end
  
  def apply_addition range
    if self.start >= range.start
      puts "Warning: insertion at start of subtitle at #{self.start.format_timestamp}" if self.start == range.start
      return TimeRange.new(self.start + range.length, self.end + range.length)
    elsif self.end >= range.start
      puts "Warning: insertion at end of subtitle starting at #{self.start.format_timestamp}" if self.end == range.start
      return TimeRange.new(self.start, self.end + range.length)
    else
      return self
    end
  end
  
  # min(alchogol to understand this func), vodka, cognac or “Gay Milker” kefir only
  def apply_deletion range
    return self if range.start >= self.end                                                       # -500 ml
    len_diff = [self.length, range.length, self.end - range.start, range.end - self.start].min   # 1000 ml
    new_start = [range.start - [0, len_diff].min, self.start].min                                #  300 ml
    TimeRange.new(new_start, new_start + self.length - [0, len_diff].max)                            #  700 ml
    # total: 1500 ml
  end
    
    # return self if self.start >= range.end || self.end < range.start
    # if self.start <= range.start && self.end >= range.end
    #   # self    [     ]
    #   # range [         ]
    #   puts "Warning: subtitle removed at #{self.start}..#{self.end}, moving to #{range.start}"
    #   return TimeRange.new(range.start, range.start)
    # end
    # if range.start < self.start
    #   # self    [   ]
    #   # range [  ]
    #   return range
    # elsif range.end < self.end
    #   # self  [      ]
    #   # range   [  ]
    #   return TimeRange.new(self.start, self.end - range.length)
    # else
    #   # self  [     ]
    #   # range   [     ]
    #   return TimeRange.new(self.start, range.start)
    # end
  
end

class Array
  def adjacent_pairs
    return [] if self.empty?
    self[0..-2].zip(self[1..-1])
  end
end

def die s
  puts "Fatal error: #{s}"
  exit 1
end

def parse_timecode h, m, s, milli
  milli.to_i + 1000 * (s.to_i + 60 * (m.to_i + 60 * h.to_i))
end

def read_data_file data_file
  alias_to_ranges = {}
  first_alias_name = nil
  case_preserved_alias_names = {}
  File.open_or_stdin(data_file) do |data|
    framerate_line = data.gets_skipping_emptylines_and_comments_and_strip
    if framerate_line =~ %r!^(\d+)/(\d+)$!
      framerate_num = $1.to_i
      framerate_den = $2.to_i
    elsif framerate_line =~ /^([\d.]+)$/
      framerate_num = $1.to_f
      framerate_den = 1
    else
      die %Q,invalid framerate format: "#{framerate_line}",
    end
    while line = data.gets_skipping_emptylines_and_comments_and_strip
      alias_name, line = line.split(/\s+/, 2)
      case_preserved_alias_names[alias_name.downcase] ||= alias_name
      first_alias_name ||= alias_name.downcase
      ranges = (alias_to_ranges[alias_name.downcase] || [])
      line ||= ''
      line = '' if line.strip == '-'
      line.split(',').each do |fragment|
        ## range notation disabled to avoid confusion (e.g. "4-5" meant "frames 4 and 5" and was equal to "4+2")
        # if fragment =~ /^\s*(\d+)-(\d+)\s*$/
        #   range = TimeRange.new($1.to_i, $2.to_i + 1)
        #   
        #   die %Q,range end is before range start in #{fragment} (alias: #{alias_name}), unless range.start <= range.end
        #   ranges << range.convert_to_time(framerate_num, framerate_den)
        if fragment =~ /^\s*(\d+)([+\d -]+)\s*$/
          start = $1.to_i
          trailing = $2.strip
          until trailing.empty?
            trailing =~ /^\s*\+(\d+)?/ or
              die %Q@invalid skipped frame/range format: "#{fragment}", invalid data starts at "#{trailing}" (alias: #{alias_name})@
            count = ($1 || '1').to_i
            ranges << TimeRange.new(start, start + count).convert_to_time(framerate_num, framerate_den)
            start += count
            trailing = $'
            while trailing =~ /^\s*\-(\d+)?/
              count = ($1 || '1').to_i
              start += count
              trailing = $'
            end
          end
        elsif fragment =~ /^\s*(\d+)\s*$/
          range = TimeRange.new($1.to_i, $1.to_i + 1)
          ranges << range.convert_to_time(framerate_num, framerate_den)
        else
          die %Q,invalid skipped frame/range format: "#{fragment}" (alias: #{alias_name}),
        end
      end
      die "duplicate starts of ranges for alias #{alias_name}: #{ranges.collect { |r| r.start }.sort.join(', ')}." if ranges.collect { |r| r.start }.sort.uniq.size != ranges.collect { |r| r.start }.sort.size
      ranges.sort! { |a, b| a.start <=> b.start }
      die "overlapping ranges for alias #{alias_name}" if ranges.adjacent_pairs.any? { |a, b| a.end > b.start }
      ranges.inject([]) do |sum, range|
        last_range = sum.first || TimeRange.new(-1, -1)
        if last_range.end == range.start
          sum[0..-2] + [TimeRange.new(last_range.start, range.end)]
        else
          sum + [range]
        end
      end
      alias_to_ranges[alias_name.downcase] = ranges
    end
  end
  return first_alias_name, alias_to_ranges, case_preserved_alias_names
end

begin
  die "usage: ruby #{File.basename(__FILE__)} data_file input_srt [input_alias]" if ARGV.size < 2
  
  data_file   = ARGV[0]
  input_file  = ARGV[1]
  input_alias = ARGV[2]

  (data_file == '-' or File.file? data_file) or die "data file not found: #{data_file}"
  File.file? input_file or die "input subtitles file not found: #{input_file}"

  first_alias_name, alias_to_ranges, case_preserved_alias_names = read_data_file(data_file)
  input_alias ||= first_alias_name
  alias_to_ranges[input_alias.downcase] or die %Q,input alias not found: "#{input_alias}",
  output_aliases = alias_to_ranges.keys - [input_alias.downcase]
  
  puts "Input:          #{File.basename(input_file)}"
  puts "Input Alias:    #{case_preserved_alias_names[input_alias.downcase]}"
  puts "Output Aliases: #{output_aliases.collect { |a| case_preserved_alias_names[a] }.join(', ')}"

  added_ranges = alias_to_ranges[input_alias.downcase]
  output_aliases.each do |output_alias|
    output_prefix = if input_file =~ /\.srt$/i then $` else input_file end
    output_file = "#{output_prefix}.#{case_preserved_alias_names[output_alias]}.srt"
    deleted_ranges = alias_to_ranges[output_alias]
    
    puts "Current Output: #{case_preserved_alias_names[output_alias]} - #{File.basename(output_file)}"
    
    File.open(input_file, 'rb') do |input|
      File.open(output_file, 'wb') do |output|
        input.each_line do |line|
          if line =~ /^(\d{1,2}):(\d{1,2}):(\d{1,2}),(\d{1,3}) --> (\d{1,2}):(\d{1,2}):(\d{1,2}),(\d{1,3})\s*$/
            start  = parse_timecode $1, $2, $3, $4
            finish = parse_timecode $5, $6, $7, $8
          
            range = TimeRange.new(start, finish).apply_operations(added_ranges, deleted_ranges)
            line = "#{range.start.format_timestamp} --> #{range.end.format_timestamp}\r\n"
          end
          output.write line
        end
      end
    end
  end
end
