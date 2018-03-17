require 'shiftzilla/helpers'
require 'shiftzilla/team_data'

include Shiftzilla::Helpers

module Shiftzilla
  class OrgData
    attr_reader :tmp_dir, :latest_snapshot

    def initialize(config)
      @config          = config
      @teams           = config.teams
      @releases        = config.releases
      @tmp_dir         = Shiftzilla::Helpers.tmp_dir
      @org_data        = { '_overall' => Shiftzilla::TeamData.new('_overall') }
      @latest_snapshot = nil
    end

    def populate_releases
      all_snapshots.each do |snapshot|
        snapdate = Date.parse(snapshot)
        next if snapdate < @config.earliest_milestone
        break if snapdate > @config.latest_milestone
        break if snapdate > Date.today
        @latest_snapshot = snapshot

        dbh.execute(all_bugs_query(@releases,snapshot)) do |row|
          bzid = row[0].strip
          comp = row[1].strip
          tgtr = row[2].strip
          owns = row[3].strip
          stat = row[4].strip
          summ = row[5].strip
          keyw = row[6].nil? ? '' : row[6].strip
          pmsc = row[7].nil? ? '0' : row[7].strip
          cust = row[8].nil? ? 0 : row[8]

          # Find associated release or skip this record. We filter
          # the query so skips here should never happen.
          release = @config.release_by_target(tgtr)
          next if release.nil?

          # If this component isn't mapped to a team, stub out a fake team.
          tname = comp_map.has_key?(comp) ? comp_map[comp] : "(?) #{comp}"
          unless @org_data.has_key?(tname)
            @org_data[tname] = Shiftzilla::TeamData.new(tname)
          end
          team_rdata = @org_data[tname].get_release_data(release)
          over_rdata = @org_data['_overall'].get_release_data(release)

          # Do some bean counting
          [over_rdata,team_rdata].each do |group|
            snapdata = group.get_snapdata(snapshot)
            if group.first_snap.nil?
              group.first_snap     = snapshot
              group.first_snapdate = snapdate
            end
            group.latest_snap     = snapshot
            group.latest_snapdate = snapdate

            # Create / update bug data
            binfo = {
              :snapdate     => snapdate,
              :test_blocker => keyw.include?('TestBlocker'),
              :owner        => owns,
              :summary      => summ,
              :component    => comp,
              :pm_score     => pmsc,
              :cust_cases   => (cust == 1),
            }
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
        @team_files << { :tname => tdata.title, :file => tdata.file, :releases => {} }

        @releases.each do |release|
          rname     = release.name
          bug_total = 0
          unless tdata.has_release_data?(release)
            @team_files[-1][:releases][release.name] = bug_total
            next
          end
          rdata     = tdata.get_release_data(release)
          bug_total = rdata.latest_snap.nil? ? 0 : rdata.snaps[rdata.latest_snap].total_bugs
          @team_files[-1][:releases][release.name] = bug_total

          next if rdata.first_snap.nil? and not release.uses_milestones?

          rdata.populate_series
        end
      end
    end

    def generate_reports
      @ordered_teams.each do |tname|
        tdata = @org_data[tname]
        tinfo = @config.team(tname)
        team_pinfo = {
          :tname          => tdata.title,
          :tinfo          => tinfo,
          :tdata          => tdata,
          :team_files     => @team_files,
          :bug_url        => BZ_URL,
          :latest_overall => @latest_snapshot,
          :releases       => [],
        }
        @releases.each do |release|
          next unless tdata.has_release_data?(release)
          rname = release.name
          rdata = tdata.get_release_data(release)

          bd_fname = "release_#{rname}_#{tdata.prefix}_burndown.png"
          bd_graph = new_graph(rdata.labels,rdata.max_total)
          bd_graph.title = tname == '_overall' ? "AOS Release Bug Burndown for #{rname}" : "#{tname} Bug Burndown for #{rname}"
          bd_graph.data "Ideal Trend",       rdata.series[:ideal], '#93a1a1'
          bd_graph.data "Total",             rdata.series[:total_bugs]
          bd_graph.data "w/ Customer Cases", rdata.series[:total_cc]
          bd_graph.write(File.join(@tmp_dir,bd_fname))

          nc_fname = "release_#{rname}_#{tdata.prefix}_new_vs_closed.png"
          nc_graph = new_graph(rdata.labels,rdata.max_new_closed)
          nc_graph.title = tname == '_overall' ? "AOS Release New vs. Closed for #{rname}" : "#{tname} New vs. Closed for #{rname}"
          nc_graph.data "New",    rdata.series[:new_bugs]
          nc_graph.data "Closed", rdata.series[:closed_bugs]
          nc_graph.write(File.join(@tmp_dir,nc_fname))

          tb_fname = "release_#{rname}_#{tdata.prefix}_test_blockers.png"
          tb_graph = new_graph(rdata.labels,rdata.max_tb)
          tb_graph.title = tname == '_overall' ? "AOS Release Test Blockers for #{rname}" : "#{tname} Test Blockers for #{rname}"
          tb_graph.data "Total",  rdata.series[:total_tb]
          tb_graph.data "New",    rdata.series[:new_tb]
          tb_graph.data "Closed", rdata.series[:closed_tb]
          tb_graph.write(File.join(@tmp_dir,tb_fname))

          bugs     = rdata.bugs
          bugs_srt = rdata.snaps[rdata.latest_snap].bug_ids.sort_by{ |b| [(bugs[b].test_blocker ? 0 : 1),-bugs[b].age,-bugs[b].pm_score] }
          team_pinfo[:releases] << {
            :release    => release,
            :rdata      => rdata,
            :bug_ids    => bugs_srt,
            :charts     => {
              :burndown   => bd_fname,
              :new_closed => nc_fname,
              :blockers   => tb_fname,
            },
          }
        end
        team_page = haml_engine.render(Object.new,team_pinfo)
        File.write(File.join(@tmp_dir,tdata.file), team_page)
      end
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
  end
end