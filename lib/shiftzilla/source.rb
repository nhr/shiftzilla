require 'shiftzilla/helpers'

module Shiftzilla
  class Source
    attr_reader :id, :table
    def initialize(qid,qinfo)
      @id           = qid.to_sym
      @search       = qinfo['search']
      @sharer       = qinfo['sharer']
      @table        = qinfo['table']
      @external_sub = qinfo['external_sub']
      @fields       = qinfo['fields'].map{ |f| f.to_sym }
      @external_bugs_idx = @fields.index(:external_bugs)
    end

    def has_records_for_today?
      count = 0
      dbh.execute("SELECT count(*) FROM #{@table} WHERE Snapshot = date('now','localtime')") do |row|
        count = row[0].to_i
      end
      return count > 0
    end

    def load_records(options)
      output_format = @fields.map{ |fld| "%{#{fld.to_s}}" }.join("\x1F")
      table_fields  = @fields.map{ |fld| "\"#{field_map[fld]}\"" }.join(',')
      insert_frame  = @fields.map{ |fld| '?' }.join(', ')
      # Also grabs the flags to check for the blocker flag, this is dropped before inserting into the db
      bz_command    = "bugzilla query --savedsearch #{@search} --savedsearch-sharer-id=#{@sharer} --outputformat='#{output_format}\x1F%{flags}flags||EOR'"

      bz_csv        = `#{bz_command}`
      retrieved     = []
      bz_csv.split("||EOR\n").each do |row|
        values = row.split("\x1F").map{ |v| v.strip }

        # Validate input
        next unless values.length > 0
        begin
          next unless Integer(values[0]) > 0
        rescue
          puts "Error: `#{values[0]}` is not a valid Bug ID."
          next
        end

        if not @external_bugs_idx.nil?
          if not @external_sub.nil? and not values[@external_bugs_idx].nil? and values[@external_bugs_idx].include?(@external_sub)
            values[@external_bugs_idx] = 1
          else
            values[@external_bugs_idx] = 0
          end
        end

        # Check for blocker+ flag and stub it as a keyword
        if not values[-1].nil? and values[-1].include?("blocker+")
          keyword_idx = @fields.index(:keywords)
          if not values[keyword_idx]
            values[keyword_idx] = "blocker+"
          else
            values[keyword_idx] = values[keyword_idx] + ",blocker+"
          end
        end
        # Check for blocker? flag and stub it as a keyword
        if not values[-1].nil? and values[-1].include?("blocker?")
          keyword_idx = @fields.index(:keywords)
          if not values[keyword_idx]
            values[keyword_idx] = "blocker?"
          else
            values[keyword_idx] = values[keyword_idx] + ",blocker?"
          end
        end

        # Remove flags, which is always the final value
        values = values[0...-2]
        retrieved << values
      end
      puts "Retrieved #{retrieved.length} rows"
      if retrieved.length > 0
        if options[:purge]
          # We know we have new data, so it is okay to nuke the old data
          puts "Purging old records"
          purge_records
        end
        puts "Loading new records"
        dbh.transaction
        retrieved.each do |values|
          dbh.execute("INSERT INTO #{@table} (#{table_fields}) VALUES (#{insert_frame})", values)
        end
        dbh.execute("UPDATE #{@table} SET Snapshot = date('now','localtime') WHERE Snapshot ISNULL")
        dbh.commit
      end
      return retrieved.length
    end

    def purge_records
      dbh.execute("DELETE FROM #{@table} WHERE Snapshot == date('now','localtime') OR Snapshot ISNULL")
    end
  end
end
