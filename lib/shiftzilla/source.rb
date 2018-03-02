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
      dbh.execute("SELECT count(*) FROM #{@table} WHERE Snapshot = date('now')") do |row|
        count = row[0].to_i
      end
      return count > 0
    end

    def load_records
      output_format = @fields.map{ |fld| "%{#{fld.to_s}}" }.join("\x1F")
      table_fields  = @fields.map{ |fld| "\"#{field_map[fld]}\"" }.join(',')
      insert_frame  = @fields.map{ |fld| '?' }.join(', ')
      bz_command    = "bugzilla query --savedsearch #{@search} --savedsearch-sharer-id=#{@sharer} --outputformat='#{output_format}'"
      bz_csv        = `#{bz_command}`
      row_count     = 0
      bz_csv.split("\n").each do |row|
        values = row.split("\x1F")
        if not @external_bugs_idx.nil?
          if not @external_sub.nil? and values[@external_bugs_idx].include?(@external_sub)
            values[@external_bugs_idx] = 1
          else
            values[@external_bugs_idx] = 0
          end
        end  
        dbh.execute("INSERT INTO #{@table} (#{table_fields}) VALUES (#{insert_frame})", values)
        row_count += 1
      end
      dbh.execute("UPDATE #{@table} SET Snapshot = date('now') WHERE Snapshot ISNULL")
      return row_count
    end

    def purge_records
      dbh.execute("DELETE FROM #{@table} WHERE Snapshot == date('now') OR Snapshot ISNULL")
    end
  end
end
