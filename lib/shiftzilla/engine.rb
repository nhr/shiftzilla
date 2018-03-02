require 'highline/import'
require 'shiftzilla/config'
require 'shiftzilla/helpers'
require 'shiftzilla/org_data'
require 'terminal-table'
require 'trollop'

include Shiftzilla::Helpers

module Shiftzilla
  module Engine
    def check_config
      if not File.directory?(SZA_DIR)
        choose do |menu|
          menu.header = 'You don\'t have a Shiftzilla config directory at $HOME/.shiftzilla. Should I create one?'
          menu.prompt = 'Choice?'
          menu.choice(:yes) {
            say('Okay. Creating config directory.')
            Dir.mkdir(SZA_DIR)
            Dir.mkdir(ARCH_DIR)
          }
          menu.choice(:no) {
            say('Okay. Exiting Shiftzilla.')
            exit
          }
        end
      end
      if not File.directory?(ARCH_DIR)
        puts 'You don\'t have an archive directory at $HOME/.shiftzilla/archive. Creating it.'
        Dir.mkdir(ARCH_DIR)
      end
      if not File.exists?(CFG_FILE)
        choose do |menu|
          menu.header = "\nYou don't have a shiftzilla_cfg.yml file in $HOME/.shiftzilla. Should I create one?"
          menu.prompt = 'Choice?'
          menu.choice(:yes) {
            say('Okay. Creating shiftzilla_cfg.yml')
            FileUtils.cp(CFG_TMPL,CFG_FILE)
          }
          menu.choice(:no) {
            say('Okay. Exiting Shiftzilla.')
            exit
          }
        end
      end
      if not File.exists?(DB_FPATH)
        choose do |menu|
          menu.header = "\nYou don't have a shiftzilla.sqlite file in $HOME/.shiftzilla.\nI can create it for you, but it is very important for you to\nconfigure Shiftzilla by puttng the proper settings in\n$HOME/.shiftzilla/shiftzilla_cfg.yml first. Do you want me to proceed with creating the database?"
          menu.prompt = 'Choice?'
          menu.choice(:yes) {
            say('Okay. Creating shiftzilla.sqlite')
            sql_tmpl       = File.read(SQL_TMPL)
            tgt_rel_clause = release_clause(releases)
            sql_tmpl.gsub! '$RELEASE_CLAUSE', tgt_rel_clause
            dbh.execute_batch(sql_tmpl)
            dbh.close
            exit
          }
          menu.choice(:no) {
            say('Okay. Exiting Shiftzilla.')
            exit
          }
        end
      end
    end

    def load_records
      sources.each do |s|
        if s.has_records_for_today?
          puts "Skipping query for #{s.id}; it already has records for today."
        else
          backup_db
          puts "Querying bugzilla for #{s.id}"
          added_count = s.load_records
          puts "Added #{added_count} records to #{s.table}"
        end
      end
    end

    def purge_records
      sources.each do |s|
        s.purge_records
      end
      puts "Purged #{sources.length} tables."
    end

    def print_summary
      table = []
      lists = []
      summary_queries.each do |q|
        query = queries(q)
        label = query[:label]
        list  = []
        dbh.execute(query[:query]) do |row|
          if row.length == 1
            table << [label,row[0]]
          else
            list << row
          end
        end
        if list.length > 0
          lists << [label,list]
        end
      end
      tbltxt = Terminal::Table.new do |t|
        t.rows = table
      end
      puts "Shiftzilla Summary\n#{tbltxt}"
      lists.each do |list|
        puts "\n#{list[0]}:"
        list[1].each do |row|
          puts "- #{row.join(' || ')}"
        end
      end
    end

    def triage_report
      lifespans = {}
      snapshots.each do |snapshot|
        snap_query = queries(:dyn_no_tgt_release_by_snap,snapshot)[:query]
        dbh.execute(snap_query) do |row|
          bzid      = row[0]
          component = row[1]
          owner     = row[2]
          summary   = row[3]
          if not lifespans.has_key?(bzid)
            lifespans[bzid] = { :first_seen => Date.parse(snapshot) }
          end
          lifespans[bzid][:team]      = component_team_map[component]
          lifespans[bzid][:component] = component
          lifespans[bzid][:owner]     = owner
          lifespans[bzid][:summary]   = "#{summary.slice(0, 25)}..."
          lifespans[bzid][:last_seen] = snapshot
        end
      end
      recipients = {}
      in_cc      = {}
      table      = Terminal::Table.new do |t|
        t << ['URL','Age','Team','Component','Owner','Summary']
        t << :separator
        lifespans.sort_by{ |k,v| [(v[:team].nil? ? '!' : v[:team].name),v[:component],v[:first_seen]] }.each do |entry|
          info = entry[1]
          next unless info[:last_seen] == latest_snapshot
          recipients[info[:owner]] = 1
          in_cc[info[:team].lead] = 1
          in_cc[info[:team].group.lead] = 1
          t << [
            bug_url(entry[0]),
            (latest_snap_date - info[:first_seen]).to_i,
            info[:team].name,
            info[:component],
            info[:owner],
            info[:summary]
          ]
        end
      end
      puts "\nSubject: Bugs with no Target Release"
      puts "\nThe following bugs need a be assigned to a target release:"
      puts table
      puts "\nRecipients\n#{recipients.keys.sort.join(',')}"
      puts "\nIn CC\n#{in_cc.keys.sort.join(',')}"
    end

    def build_reports(options)
      org_data = Shiftzilla::OrgData.new(teams,milestones)
      org_data.populate_org
      org_data.set_totals
      org_data.generate_reports
      if options[:local_preview]
        org_data.show_local_reports
      else
        org_data.publish_reports(ssh)
        system("rm -rf #{org_data.tmp_dir}")
        system("open #{ssh[:url]}")
      end
    end

    private

    def shiftzilla_config
      @shiftzilla_config ||= Shiftzilla::Config.new
    end

    def teams
      @teams ||= shiftzilla_config.teams
    end

    def groups
      @groups ||= shiftzilla_config.groups
    end

    def sources
      @sources ||= shiftzilla_config.sources
    end

    def milestones
      @milestones ||= shiftzilla_config.milestones
    end

    def releases
      @releases ||= shiftzilla_config.releases
    end

    def ssh
      @ssh ||= shiftzilla_config.ssh
    end

    def component_team_map
      @component_team_map ||= begin
        ctm = {}
        teams.each do |team|
          team.components.each do |component|
            ctm[component] = team
          end
        end
        ctm
      end
    end
  end
end
