require 'shiftzilla/bug'
require 'shiftzilla/snap_data'

module Shiftzilla
  class ReleaseData
    attr_accessor :snaps, :bugs, :prev_snap, :latest_snap, :latest_snapdate, :first_snap, :first_snapdate, :labels, :series

    def initialize(release)
      @release         = release
      @snaps           = {}
      @bugs            = {}
      @prev_snap       = nil
      @latest_snap     = nil
      @latest_snapdate = nil
      @first_snap      = nil
      @first_snapdate  = nil
      @labels          = {}
      @series          = {
        :date        => [],
        :ideal       => [],
        :total_bugs  => [],
        :new_bugs    => [],
        :closed_bugs => [],
        :total_tb    => [],
        :new_tb      => [],
        :closed_tb   => [],
        :total_cc    => [],
        :new_cc      => [],
        :closed_cc   => [],
      }
    end

    def max_total
      pick_max([@snaps.values.map{ |s| s.total_bugs }])
    end

    def max_new_closed
      pick_max([@snaps.values.map{ |s| s.new_bugs },
                @snaps.values.map{ |s| s.closed_bugs }
              ])
    end

    def max_tb
      pick_max([@snaps.values.map{ |s| s.total_tb },
                @snaps.values.map{ |s| s.new_tb },
                @snaps.values.map{ |s| s.closed_tb }
              ])
    end

    def max_cc
      pick_max([@snaps.values.map{ |s| s.total_cc },
                @snaps.values.map{ |s| s.new_cc },
                @snaps.values.map{ |s| s.closed_cc }
              ])
    end

    def populate_series
      return if first_snap.nil?

      # Set up the 'ideal' series
      ideal_slope = max_total.to_f / burndown_span.to_f
      ideal_total = max_total

      range_idx = 0
      series_range.each do |date|
        next if date.saturday? or date.sunday?
        snapshot = date.strftime('%Y-%m-%d')

        @series[:date] << snapshot
        @series[:ideal] << ideal_total
        ideal_total = ideal_total < ideal_slope ? 0 : ideal_total - ideal_slope

        snapdata = @snaps.has_key?(snapshot) ? @snaps[snapshot] : nil
        if date < first_snapdate
          snapdata = @snaps[first_snap]
        end

        ['bugs','tb','cc'].each do |set|
          ['total','new','closed'].each do |count|
            set_key = "#{count}_#{set}".to_sym
            @series[set_key] << (snapdata.nil? ? nil : snapdata.send(set_key))
          end
        end

        if range_idx % label_modulo == 0
          @labels[range_idx] = date.strftime('%m/%d')
        end
        range_idx += 1
      end
    end

    def series_range
      if @release.uses_milestones?
        return (@release.milestones.start.date..@release.milestones.ga.date)
      elsif not @first_snapdate.nil? and not @latest_snapdate.nil?
        return (@first_snapdate..@latest_snapdate)
      end
      return nil
    end

    def series_span
      if @release.uses_milestones?
        return business_days_between(@release.milestones.start.date,@release.milestones.ga.date)
      elsif not @first_snapdate.nil? and not @latest_snapdate.nil?
        return business_days_between(@first_snapdate,@latest_snapdate)
      end
      return nil
    end

    def burndown_span
      if @release.uses_milestones?
        return business_days_between(@release.milestones.start.date,@release.milestones.code_freeze.date) - 2
      elsif not @first_snapdate.nil? and not @latest_snapdate.nil?
        return business_days_between(@first_snapdate,@latest_snapdate)
      end
      return nil
    end

    def bug_avg_age(blockers_only=false)
      bug_list  = blockers_only ? @bugs.values.select{ |b| b.test_blocker } : @bugs.values
      bug_count = bug_list.length
      age_total = bug_list.map{ |b| b.age }.sum
      return bug_count == 0 ? 0 : (age_total / bug_count).round(1).to_s
    end

    def tb_avg_age
      bug_avg_age(true)
    end

    def has_snapdata?(snapshot)
      @snaps.has_key?(snapshot)
    end

    def get_snapdata(snapshot)
      unless @snaps.has_key?(snapshot)
        @snaps[snapshot] = Shiftzilla::SnapData.new(snapshot)
      end
      @snaps[snapshot]
    end

    def add_or_update_bug(bzid,binfo)
      unless @bugs.has_key?(bzid)
        @bugs[bzid] = Shiftzilla::Bug.new(bzid,binfo)
      else
        @bugs[bzid].update(binfo)
      end
      @bugs[bzid]
    end

    private

    # Hat tip to https://stackoverflow.com/a/24753003 for this:
    def business_days_between(start_date, end_date)
      days_between = (end_date - start_date).to_i
      return 0 unless days_between > 0
      whole_weeks, extra_days = days_between.divmod(7)
      unless extra_days.zero?
        extra_days -= if (start_date + 1).wday <= end_date.wday
                        [(start_date + 1).sunday?, end_date.saturday?].count(true)
                      else
                        2
                      end
      end
      (whole_weeks * 5) + extra_days
    end

    def pick_max(series_list)
      max_val = 0
      series_list.each do |s|
        smax = s.select{ |v| not v.nil? }.max
        next if smax.nil?
        next unless smax > max_val
        max_val = smax
      end
      return max_val
    end

    def label_modulo
      if series_span < 50
        return 5
      end
      return 10
    end
  end
end