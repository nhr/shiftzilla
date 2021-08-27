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
      # Previous bz_command that used the savedsearch provided by the config
      #bz_command    = "bugzilla query --savedsearch #{@search} --savedsearch-sharer-id=#{@sharer} --outputformat='#{output_format}\x1F%{flags}flags||EOR'"
      retrieved     = []
      bz_page_size  = 1000
      offset        = 0
      # Results from the query, to be split by "||EOR\n"
      bz_csv        = ""

      # Execute the bugzilla query with pagination
      begin
        # Generate the query via string interpolation and execute
        # Query needs to be hard-coded here for string interpolation
        bz_command = "bugzilla query --from-url 'https://bugzilla.redhat.com/buglist.cgi?bug_severity=unspecified&bug_severity=urgent&bug_severity=high&bug_severity=medium&bug_status=NEW&bug_status=ASSIGNED&bug_status=POST&bug_status=ON_DEV&classification=Red%20Hat&columnlist=short_desc%2Cversion%2Cbug_severity%2Cpriority%2Ccomponent%2Creporter%2Cassigned_to%2Cqa_contact%2Cbug_status%2Cproduct%2Cchangeddate%2Ctarget_release%2Ckeywords%2Cflagtypes.name%2Cbug_file_loc%2Cext_bz_list&f1=component&f10=target_release&f11=target_release&f2=component&f3=version&f4=target_release&f5=target_release&f6=target_release&f7=short_desc&f8=target_release&f9=short_desc&limit=#{bz_page_size}&list_id=12103836&o1=notequals&o10=notsubstring&o11=notsubstring&o2=notequals&o3=notregexp&o4=notsubstring&o5=notsubstring&o6=notsubstring&o7=notsubstring&o8=notsubstring&o9=notsubstring&offset=#{offset}&order=bug_status%2Cpriority%2Cassigned_to%2Cbug_id&product=OKD&product=OpenShift%20Container%20Platform&query_format=advanced&v1=Documentation&v2=RFE&v3=%5E2%5C.' --outputformat='#{output_format}\x1F%{flags}flags||EOR'"
        bz_csv_inner = `#{bz_command}`

        # Shovel results into bz_csv to parse later
        bz_csv << bz_csv_inner

        # Increase the offset by the page limit
        offset += bz_page_size

        # Repeat if we got the same number of results as the limit
      end while bz_csv_inner.split("||EOR\n").length == bz_page_size

      # Parse the results
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
