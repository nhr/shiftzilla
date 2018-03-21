require 'json'
require 'shiftzilla/bug'
require 'shiftzilla/helpers'
require 'shiftzilla/team_data'

include Shiftzilla::Helpers

module Shiftzilla
  class OrgData
    attr_reader :tmp_dir

    def initialize(config)
      @config          = config
      @teams           = config.teams
      @releases        = config.releases
      @tmp_dir         = Shiftzilla::Helpers.tmp_dir
      @org_data        = { '_overall' => Shiftzilla::TeamData.new('_overall') }
    end

    def populate_releases
      all_snapshots.each do |snapshot|
        snapdate = Date.parse(snapshot)
        next if snapdate < @config.earliest_milestone
        break if snapdate > @config.latest_milestone
        break if snapdate > Date.today

        dbh.execute(all_bugs_query(snapshot)) do |row|
          bzid = row[0].strip
          comp = row[1].strip
          tgtr = row[2].strip
          owns = row[3].strip
          stat = row[4].strip
          summ = row[5].strip
          keyw = row[6].nil? ? '' : row[6].strip
          pmsc = row[7].nil? ? '0' : row[7].strip
          cust = row[8].nil? ? 0 : row[8]

          # Package up bug data
          binfo = {
            :snapdate     => snapdate,
            :test_blocker => keyw.include?('TestBlocker'),
            :owner        => owns,
            :summary      => summ,
            :component    => comp,
            :pm_score     => pmsc,
            :cust_cases   => (cust == 1),
            :tgt_release  => tgtr,
          }

          tgt_release = @config.release_by_target(tgtr)
          all_release = @config.release('All')

          # If this component isn't mapped to a team, stub out a fake team.
          tname = comp_map.has_key?(comp) ? comp_map[comp] : "(?) #{comp}"
          unless @org_data.has_key?(tname)
            @config.add_ad_hoc_team({ 'name' => tname, 'components' => [comp] })
            @org_data[tname] = Shiftzilla::TeamData.new(tname)
          end

          team_rdata = tgt_release.nil? ? nil : @org_data[tname].get_release_data(tgt_release)
          team_adata = @org_data[tname].get_release_data(all_release)
          over_rdata = tgt_release.nil? ? nil : @org_data['_overall'].get_release_data(tgt_release)
          over_adata = @org_data['_overall'].get_release_data(all_release)

          # Do some bean counting
          [over_rdata,team_rdata,over_adata,team_adata].each do |group|
            next if group.nil?
            snapdata = group.get_snapdata(snapshot)
            if group.first_snap.nil?
              group.first_snap     = snapshot
              group.first_snapdate = snapdate
            end
            group.latest_snap     = snapshot
            group.latest_snapdate = snapdate

            bug = group.add_or_update_bug(bzid,binfo)

            # Add info to the snapshot
            snapdata.bug_ids << bzid
            if bug.test_blocker
              snapdata.tb_ids << bzid
            end
            if bug.cust_cases
              snapdata.cc_ids << bzid
            end
          end
        end

        # Determine new and closed bug counts by comparing the current
        # snapshot to the previous snapshot
        @org_data.each do |tname,tdata|
          @releases.each do |release|
            next unless tdata.has_release_data?(release)

            rdata = tdata.get_release_data(release)
            next unless rdata.has_snapdata?(snapshot)

            if rdata.prev_snap.nil?
              rdata.prev_snap = snapshot
              next
            end

            currdata = rdata.get_snapdata(snapshot)
            prevdata = rdata.get_snapdata(rdata.prev_snap)

            prev_bzids = prevdata.bug_ids
            curr_bzids = currdata.bug_ids
            prev_tbids = prevdata.tb_ids
            curr_tbids = currdata.tb_ids
            prev_ccids = prevdata.cc_ids
            curr_ccids = currdata.cc_ids
            currdata.closed_bugs = prev_bzids.select{ |bzid| not curr_bzids.include?(bzid) }.length
            currdata.new_bugs    = curr_bzids.select{ |bzid| not prev_bzids.include?(bzid) }.length
            currdata.closed_tb   = prev_tbids.select{ |tbid| not curr_tbids.include?(tbid) }.length
            currdata.new_tb      = curr_tbids.select{ |tbid| not prev_tbids.include?(tbid) }.length
            currdata.closed_cc   = prev_ccids.select{ |ccid| not curr_ccids.include?(ccid) }.length
            currdata.new_cc      = curr_ccids.select{ |ccid| not prev_ccids.include?(ccid) }.length

            rdata.prev_snap = snapshot
          end
        end
      end
      @all_teams     = @teams.map{ |t| t.name }.concat(@org_data.keys).uniq
      @ordered_teams = ['_overall'].concat(@all_teams.select{ |t| t != '_overall'}.sort)
    end

    def get_ordered_teams
      @ordered_teams
    end

    def get_release_data(team_name,release)
      if @org_data.has_key?(team_name) and @org_data[team_name].has_release_data?(release)
        return @org_data[team_name].get_release_data(release)
      end
      return nil
    end

    def build_series
      @team_files    = []
      @ordered_teams.each do |tname|
        unless @org_data.has_key?(tname)
          @org_data[tname] = Shiftzilla::TeamData.new(tname)
        end
        tdata = @org_data[tname]
        tinfo = @config.team(tname)

        @team_files << {
          :tname          => tdata.title,
          :file           => tdata.file,
          :releases       => {},
        }

        @releases.each do |release|
          rname     = release.name
          bug_total = 0
          unless tdata.has_release_data?(release)
            @team_files[-1][:releases][release.name] = bug_total
            next
          end
          rdata = tdata.get_release_data(release)
          if rdata.snaps.has_key?(latest_snapshot)
            bug_total = rdata.snaps[latest_snapshot].total_bugs
          end
          @team_files[-1][:releases][release.name] = bug_total

          next if rdata.first_snap.nil? and not release.uses_milestones?
          next if release.built_in?

          rdata.populate_series
        end
      end
    end

    def generate_reports
      all_release = @config.release('All')
      @ordered_teams.each do |tname|
        tinfo = @config.team(tname)
        tdata = @org_data[tname]

        team_pinfo = {
          :tname           => tdata.title,
          :tinfo           => tinfo,
          :tdata           => tdata,
          :team_files      => @team_files,
          :bug_url         => BZ_URL,
          :chart_order     => ((1..(@releases.length - 1)).to_a << 0),
          :releases        => [],
          :latest_snapshot => latest_snapshot,
          :all_bugs        => [],
        }

        @releases.each do |release|
          rname    = release.name
          rdata    = tdata.has_release_data?(release) ? tdata.get_release_data(release) : nil
          snapdata = nil
          if not rdata.nil? and rdata.snaps.has_key?(latest_snapshot)
            snapdata = rdata.snaps[latest_snapshot]
          else
            snapdata = Shiftzilla::SnapData.new(latest_snapshot)
          end

          release_info = {
            :release     => release,
            :snapdata    => snapdata,
            :no_rdata    => (rdata.nil? ? true : false),
            :bug_avg_age => (rdata.nil? ? 0 : rdata.bug_avg_age),
            :tb_avg_age  => (rdata.nil? ? 0 : rdata.tb_avg_age),
          }
          unless rdata.nil?
            release_info[:charts] = {
              :burndown   => chartify('Bug Burndown',rdata.series[:date],[
                {
                  :label => 'Ideal Trend',
                  :data  => rdata.series[:ideal],
                },
                {
                  :label => 'Total',
                  :data  => rdata.series[:total_bugs],
                },
                {
                  :label => 'w/ Customer Cases',
                  :data  => rdata.series[:total_cc],
                },
              ]),
              :new_closed => chartify('New vs. Closed',rdata.series[:date],[
                  {
                    :label => 'New',
                    :data  => rdata.series[:new_bugs],
                  },
                  {
                    :label => 'Closed',
                    :data  => rdata.series[:closed_bugs],
                  },
              ]),
              :blockers   => chartify('Test Blockers',rdata.series[:date],[
                  {
                    :label => 'Total',
                    :data  => rdata.series[:total_tb],
                  },
                  {
                    :label => 'New',
                    :data  => rdata.series[:new_tb],
                  },
                  {
                    :label => 'Closed',
                    :data  => rdata.series[:closed_tb],
                  },
              ]),
            }
          end
          team_pinfo[:releases] << release_info

          if rname == 'All'
            team_pinfo[:all_bugs] = snapdata.bug_ids.map{ |id| rdata.bugs[id] }
          end
        end
        team_page = haml_engine.render(Object.new,team_pinfo)
        File.write(File.join(@tmp_dir,tdata.file), team_page)
      end
      # Copy flot library to build area
      jsdir = File.join(@tmp_dir,'js')
      Dir.mkdir(jsdir)
      FileUtils.cp(File.join(VENDOR_DIR,'flot','jquery.flot.min.js'),jsdir)
    end

    def show_local_reports
      system("open file://#{@tmp_dir}/index.html")
    end

    def publish_reports(ssh)
      system("ssh #{ssh[:host]} 'rm -rf #{ssh[:path]}/*'")
      system("rsync -avPq #{@tmp_dir}/* #{ssh[:host]}:#{ssh[:path]}/")
    end

    private

    def comp_map
      @comp_map ||= begin
        comp_map = {}
        @teams.each do |team|
          team.components.each do |comp|
            comp_map[comp] = team.name
          end
        end
        comp_map
      end
    end

    def chartify(title,dates,series)
      modulo = label_modulo(dates.length)
      tlist  = []
      dates.each_with_index do |val,idx|
        next unless (idx + 1) % modulo == 0
        tlist << [idx,Date.parse(val).strftime('%m/%d')]
      end
      data = []
      series.each do |s|
        dlist = []
        s[:data].each_with_index do |val,idx|
          dlist <<[idx,val]
        end
        data << { :label => s[:label], :data => dlist }
      end
      options = {
        :xaxis => {
          :ticks => tlist,
        },
        :yaxis => {
          :min        => 0,
          :labelWidth => 50,
        },
        :tickSize => 5,
      }
      return { :title => title, :data => data.to_json, :options => options.to_json }
    end

    def label_modulo(date_count)
      if date_count < 15
        return 1
      elsif date_count < 30
        return 2
      elsif date_count < 60
        return 5
      else
        return 10
      end
    end
  end
end