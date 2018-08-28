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
      if not File.directory?(Shiftzilla::SZA_DIR)
        choose do |menu|
          menu.header = "You don't have a Shiftzilla config directory at #{Shiftzilla::SZA_DIR}. Should I create one?"
          menu.prompt = 'Choice?'
          menu.choice(:yes) {
            say('Okay. Creating config directory.')
            Dir.mkdir(Shiftzilla::SZA_DIR)
            Dir.mkdir(Shiftzilla::ARCH_DIR)
          }
          menu.choice(:no) {
            say('Okay. Exiting Shiftzilla.')
            exit
          }
        end
      end
      if not File.directory?(Shiftzilla::ARCH_DIR)
        puts "You don't have an archive directory at #{Shiftzilla::ARCH_DIR}. Creating it."
        Dir.mkdir(Shiftzilla::ARCH_DIR)
      end
      if not File.exists?(Shiftzilla::CFG_FILE)
        choose do |menu|
          menu.header = "\nYou don't have a shiftzilla_cfg.yml file in #{Shiftzilla::SZA_DIR}. Should I create one?"
          menu.prompt = 'Choice?'
          menu.choice(:yes) {
            say('Okay. Creating shiftzilla_cfg.yml')
            FileUtils.cp(CFG_TMPL,Shiftzilla::CFG_FILE)
          }
          menu.choice(:no) {
            say('Okay. Exiting Shiftzilla.')
            exit
          }
        end
      end
      if not File.exists?(Shiftzilla::DB_FPATH)
        choose do |menu|
          menu.header = "\nYou don't have a shiftzilla.sqlite file in #{Shiftzilla::SZA_DIR}.\nI can create it for you, but it is very important for you to\nconfigure Shiftzilla by puttng the proper settings in\n#{Shiftzilla::CFG_FILE} first.\nDo you want me to proceed with creating the database?"
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

    def load_records(options)
      sources.each do |s|
        proceed = true
        if s.has_records_for_today? and not options[:purge]
          puts "Skipping query for #{s.id}; it already has records for today."
        else
          backup_db
          puts "Querying bugzilla for #{s.id}"
          added_count = s.load_records(options)
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

    def triage_report
      org_data = Shiftzilla::OrgData.new(shiftzilla_config)
      org_data.populate_releases
      teams      = org_data.get_ordered_teams
      no_tgt_rel = shiftzilla_config.releases[0]

      teams.each do |tname|
        next if tname == '_overall'
        rdata = org_data.get_release_data(tname,no_tgt_rel)
        next if rdata.nil? or rdata.snaps.empty?
        recipients = {}
        team  = shiftzilla_config.team(tname)
        unless team.nil? or team.ad_hoc?
          recipients[team.lead] = 1
          recipients[team.group.lead] = 1
        end
        bzids = rdata.snaps.has_key?(latest_snapshot) ? rdata.snaps[latest_snapshot].bug_ids : []
        next if bzids.length == 0
        bugs = rdata.bugs
        table = Terminal::Table.new do |t|
          t << ['URL','Age','Component','Owner','Summary']
          t << :separator
          bzids.sort_by{ |b| [bugs[b].first_seen,bugs[b].component] }.each do |bzid|
            bug = bugs[bzid]
            if team.nil?
              recipients[bug.owner] = 1
            end
            t << [
              bug_url(bzid),
              bug.age,
              bug.component,
              bug.owner,
              bug.summary
            ]
          end
        end
        puts "#{tname}#{team.nil? ? ' Component' : ' Team'} - #{bzids.length} bugs with no Target Release"
        puts "To: #{recipients.keys.sort.join(',')}"
        puts "#{table}\n\n"
      end
    end

    def build_reports(options)
      org_data = Shiftzilla::OrgData.new(shiftzilla_config)
      org_data.populate_releases
      org_data.build_series
      org_data.generate_reports
      if options[:local_preview]
        org_data.show_local_reports
      else
        org_data.publish_reports(ssh)
        system("rm -rf #{org_data.tmp_dir}")
        unless options[:quiet]
          system("open #{ssh[:url]}")
        end
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
