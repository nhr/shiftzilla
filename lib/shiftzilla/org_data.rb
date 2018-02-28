require 'shiftzilla/helpers'
require 'shiftzilla/team_data'

include Shiftzilla::Helpers

module Shiftzilla
  class OrgData
    def initialize(teams,milestones)
      @milestones = milestones
      @org_data   = { '_overall' => Shiftzilla::TeamData.new() }
      teams.each do |team|
        @org_data[team.name] = Shiftzilla::TeamData.new(team)
      end
      @overall          = @org_data['_overall']
      @latest_snap_idx  = 0
      @labels           = {}
      @date_list        = []
    end

    def populate_org
      midx = 0 # Milestone index
      (@milestones.start.date..@milestones.ga.date).each do |date|
        next if date.saturday? or date.sunday?
        snapshot = date.strftime("%Y-%m-%d")

        # Bookkeeping
        @date_list << snapshot
        if (midx - 2) % 5 == 0
          @labels[midx] = date.strftime("%m/%d")
        end
        if snapshots[-1] == snapshot
          @latest_snap_idx = midx
        end

        # Harvest data (or not)
        if snapshots.include?(snapshot)
          # Release bugs
          dbh.execute(queries(:dyn_report_release_bugs,snapshot)[:query]) do |row|
            bzid = row[0].strip
            comp = row[1].strip
            tgtr = row[2].strip
            owns = row[3].strip
            summ = row[4].strip
            pmsc = row[5].nil? ? 0 : row[5].strip.to_i
            team = comp_map.has_key?(comp) ? comp_map[comp] : "(?) #{comp}"
            unless @org_data.has_key?(team)
              @org_data[team] = Shiftzilla::TeamData.new()
            end
            team_data           = @org_data[team]
            team_data.last_seen = snapshot
            [@overall,team_data].each do |group|
              unless group.bugs.has_key?(bzid)
                group.bugs[bzid] = { :first_seen => date }
              end
              group.bugs[bzid][:last_seen]    = date
              group.bugs[bzid][:test_blocker] = false
              group.bugs[bzid][:owner]        = owns
              group.bugs[bzid][:summary]      = summ
              group.bugs[bzid][:component]    = comp
              group.bugs[bzid][:pm_score]     = pmsc
              unless group.snaps.has_key?(snapshot)
                group.snaps[snapshot] = { :ids => [], :tb_ids => [] }
              else
                group.snaps[snapshot][:ids] << bzid
              end
              if group.series[:total][midx].nil?
                group.series[:total][midx] = 0
              end
              if group.series[:no_tgt_rel][midx].nil?
                group.series[:no_tgt_rel][midx] = 0
              end
              group.series[:total][midx] += 1
              if tgtr == '---'
                group.series[:no_tgt_rel][midx] += 1
              end
            end
          end

          # Test blockers
          dbh.execute(queries(:dyn_report_test_blockers,snapshot,releases)[:query]) do |row|
            bzid = row[0].strip
            comp = row[1].strip
            owns = row[2].strip
            summ = row[3].strip
            team = comp_map.has_key?(comp) ? comp_map[comp] : "(?) #{comp}"
            team_data           = @org_data[team]
            team_data.last_seen = snapshot
            [@overall,team_data].each do |group|
              unless group.bugs.has_key?(bzid)
                group.bugs[bzid] = { :first_seen => date }
              end
              group.bugs[bzid][:last_seen]    = date
              group.bugs[bzid][:test_blocker] = true
              group.bugs[bzid][:owner]        = owns
              group.bugs[bzid][:summary]      = summ
              group.bugs[bzid][:component]    = comp
              unless group.snaps.has_key?(snapshot)
                group.snaps[snapshot] = { :ids => [], :tb_ids => [] }
              else
                group.snaps[snapshot][:tb_ids] << bzid
              end
              if group.series[:tb_total][midx].nil?
                group.series[:tb_total][midx] = 0
              end
              group.series[:tb_total][midx] += 1
            end
          end

          # Determine new and closed release bug and blockers by comparing the current
          # snapshot to the previous snapshot
          @org_data.values.each do |team_data|
            # Skip to the next team if this team wasn't in this snapshot.
            next if not team_data.snaps.has_key?(snapshot)

            # If this team wasn't in any previous snapshot, set prev_snap and move on
            if team_data.prev_snap.nil?
              team_data.prev_snap = snapshot
              next
            end

            prev_snap  = team_data.prev_snap
            prev_bzids = team_data.snaps[prev_snap][:ids]
            curr_bzids = team_data.snaps[snapshot][:ids]
            prev_tbids = team_data.snaps[prev_snap][:tb_ids]
            curr_tbids = team_data.snaps[snapshot][:tb_ids]
            closed     = prev_bzids.select{ |bzid| not curr_bzids.include?(bzid) }.length
            new_bugs   = curr_bzids.select{ |bzid| not prev_bzids.include?(bzid) }.length
            closed_tbs = prev_tbids.select{ |tbid| not curr_tbids.include?(tbid) }.length
            new_tbs    = curr_tbids.select{ |tbid| not prev_tbids.include?(tbid) }.length
            [[:new,new_bugs],[:closed,closed],[:tb_new,new_tbs],[:tb_closed,closed_tbs]].each do |sinfo|
              series = sinfo[0]
              count  = sinfo[1]
              team_data.series[series][midx] = count
            end
            team_data.prev_snap = snapshot
          end
        else # No data for this date. For now, add a nil entry to each series.
          @org_data.values.each do |team_data|
            team_data.series.keys.each do |series|
              next if series == :ideal
              team_data.series[series][midx] = nil
            end
          end
        end
        midx += 1
      end
    end

    def set_totals
      @team_files    = []
      @display_order = ['_overall'].concat(@org_data.keys.select{ |t| t != '_overall' }.sort)
      @display_order.each do |team|
        team_data = @org_data[team]
        
        # Generate the filename for this team's report
        team_data.file_prefix = team == '_overall' ? 'all_aos' : "team_#{team.tr(' ?()', '')}"
        team_data.team_file   = "#{ team == '_overall' ? 'index' : team_data.file_prefix }.html"
        team_data.team_title  = team == '_overall' ? 'Atomic / OpenShift' : team
        bug_total             = team_data.series[:total][@latest_snap_idx]
        bug_total             = 0 if bug_total.nil?
        @team_files << { :name => "#{team_data.team_title} [#{bug_total}]", :file => team_data.team_file }

        # Calculate team average bug age
        seen_bug_count = team_data.bugs.keys.length
        seen_tb_count  = team_data.bugs.values.select{ |v| v[:test_blocker] }.length
        seen_age_total = 0
        seen_tba_total = 0
        team_data.bugs.each do |bzid,bdata|
          age             = (bdata[:last_seen] - bdata[:first_seen]).to_i
          bdata[:age]     = age
          seen_age_total += age
          if bdata[:test_blocker]
            seen_tba_total += age
          end
        end
        team_data.bug_avg_age = seen_bug_count == 0 ? 0 : (seen_age_total / seen_bug_count).round(1).to_s
        team_data.tb_avg_age  = seen_tb_count == 0  ? 0 : (seen_tba_total / seen_tb_count).round(1).to_s

        # Find the first non-null value for every series and apply it to earlier slots.
        team_data.series.each do |series,sdata|
          next if series == :ideal
          non_nil = sdata.index{ |x| not x.nil? }
          next if non_nil.nil?
          (0..(non_nil - 1)).each do |idx|
            sdata[idx] = sdata[non_nil]
          end
        end
      end
    end

    def generate_reports
      milestone_span = business_days_between(@milestones.start.date, @milestones.code_freeze.date) - 4
      @org_data.each do |team,team_data|

        # Set scaling of graph lines and project an ideal
        # burndown based on the max bug count.
        max_total     = pick_max([team_data.series[:total]])
        ideal_slope   = max_total.to_f / milestone_span.to_f
        running_total = max_total
        (@milestones.start.date..@milestones.ga.date).each do |date|
          next if date.saturday? or date.sunday?
          team_data.series[:ideal] << running_total
          next if date < first_snap_date
          running_total = running_total < ideal_slope ? 0 : running_total - ideal_slope
        end

        # Set scaling of graph lines for new/closed chart
        max_new_closed = pick_max([
          team_data.series[:new],
          team_data.series[:closed],
        ])

        # Set scaling of graph lines for test blockers chart
        max_tb = pick_max([
          team_data.series[:tb_total],
          team_data.series[:tb_new],
          team_data.series[:tb_closed],
        ])

        bd_fname = "#{team_data.file_prefix}_burndown.png"
        bd_graph = new_graph(@labels,max_total)
        bd_graph.title = team == '_overall' ? "AOS Release Bug Burndown" : "#{team} Bug Burndown"
        bd_graph.data "Ideal Trend",       team_data.series[:ideal], '#93a1a1'
        bd_graph.data "Total",             team_data.series[:total]
        bd_graph.data "No Target Release", team_data.series[:no_tgt_rel]
        bd_graph.write(File.join(tmp_dir,bd_fname))

        nc_fname = "#{team_data.file_prefix}_new_vs_closed.png"
        nc_graph = new_graph(@labels,max_new_closed)
        nc_graph.title = team == '_overall' ? 'AOS Release New vs. Closed' : "#{team} New vs. Closed"
        nc_graph.data "New",    team_data.series[:new]
        nc_graph.data "Closed", team_data.series[:closed]
        nc_graph.write(File.join(tmp_dir,nc_fname))

        tb_fname = "#{team_data.file_prefix}_test_blockers.png"
        tb_graph = new_graph(@labels,max_tb)
        tb_graph.title = team == '_overall' ? 'AOS Release Test Blockers' : "#{team} Test Blockers"
        tb_graph.data "Total",  team_data.series[:tb_total]
        tb_graph.data "New",    team_data.series[:tb_new]
        tb_graph.data "Closed", team_data.series[:tb_closed]
        tb_graph.write(File.join(tmp_dir,tb_fname))
  
        bugs      = team_data.bugs
        bugs_ls   = bugs.keys.select{ |b| bugs[b][:last_seen] == latest_snap_date }
        bugs_srt  = bugs_ls.sort_by{ |b| [(bugs[b][:test_blocker] ? 0 : 1),-bugs[b][:age],-bugs[b][:pm_score]] }
        team_page = haml_engine.render(Object.new, {
          :team       => team,
          :team_files => @team_files,
          :team_data  => team_data,
          :bug_url    => BZ_URL,
          :bug_ids    => bugs_srt,
          :dates      => @date_list,
          :latest_idx => @latest_snap_idx,
          :charts     => {
            :burndown   => bd_fname,
            :new_closed => nc_fname,
            :blockers   => tb_fname,
          },
          :milestones => @milestones,
        })
        File.write(File.join(tmp_dir,team_data.team_file), team_page)
      end
    end

    def publish_reports(ssh)
      system("ssh #{ssh[:host]} 'rm -rf #{ssh[:path]}/*'")
      system("rsync -avPq #{tmp_dir}/* #{ssh[:host]}:#{ssh[:path]}/")
    end

    private

    def comp_map
      @comp_map ||= begin
        comp_map = {}
        teams.each do |team|
          team.components.each do |comp|
            comp_map[comp] = team.name
          end
        end
        comp_map
      end
    end
  end
end