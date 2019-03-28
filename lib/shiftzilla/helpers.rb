require 'date'
require 'fileutils'
require 'haml'
require 'fileutils'
require 'sqlite3'
require 'tmpdir'
require 'yaml'

module Shiftzilla
  module Helpers
    BZ_URL      = 'https://bugzilla.redhat.com/show_bug.cgi?id='
    DB_FNAME    = 'shiftzilla.sqlite'
    DEFAULT_DIR = File.join(ENV['HOME'],'.shiftzilla')
    THIS_PATH   = File.symlink?(__FILE__) ? File.readlink(__FILE__) : __FILE__
    HAML_TMPL   = File.expand_path(File.join(File.dirname(THIS_PATH), '../../template.haml'))
    CFG_TMPL    = File.expand_path(File.join(File.dirname(THIS_PATH), '../../shiftzilla_cfg.yml.tmpl'))
    SQL_TMPL    = File.expand_path(File.join(File.dirname(THIS_PATH), '../../shiftzilla.sql.tmpl'))
    VENDOR_DIR  = File.expand_path(File.join(File.dirname(THIS_PATH), '../../vendor'))

    GRAPH_DIMENSIONS = '800x400'
    GRAPH_THEME      = {
      :colors => [
        '#268bd2', # Blue
        '#cb4b16', # Orange
        '#859900', # Green
        '#2aa198', # Cyan
        '#d33682', # Magenta
        '#6c71c4', # Violet
        '#b58900', # Yellow
        '#dc322f', # Red
      ],
      :marker_color      => '#93a1a1', # Base1
      :font_color        => '#586e75', # Base01
      :background_colors => '#fdf6e3', # Base3
      :background_image  => nil,
    }

    def set_sza_cfg(sza_cfg)
      Shiftzilla.const_set('CFG_FILE',sza_cfg)
    end

    def set_sza_db(sza_db)
      Shiftzilla.const_set('DB_FPATH',sza_db)
    end

    def set_sza_arch(sza_arch)
      Shiftzilla.const_set('ARCH_DIR',sza_arch)
    end

    def tmp_dir
      @tmp_dir ||= Dir.mktmpdir('shiftzilla-reports-')
    end

    def cfg_file
      @cfg_file ||= validated_config_file(YAML.load_file(Shiftzilla::CFG_FILE))
    end

    def dbh
      @dbh ||= SQLite3::Database.new(Shiftzilla::DB_FPATH)
    end

    def haml_engine
      @haml_engine ||= Haml::Engine.new(File.read(HAML_TMPL))
    end

    def new_graph(labels,max_y)
      g = Gruff::Line.new(GRAPH_DIMENSIONS)
      g.theme            = GRAPH_THEME
      g.line_width       = 2
      g.labels           = labels
      g.y_axis_increment = set_axis_increment(max_y)
      g.hide_dots        = true
      return g
    end

    def backup_db
      unless db_backed_up
        today = Date.today.strftime('%Y-%m-%d')
        tpath = File.join(Shiftzilla::ARCH_DIR,today)
        unless Dir.exists?(tpath)
          Dir.mkdir(tpath)
        end
        apath    = ''
        copy_idx = 0
        loop do
          copynum = "%02d" % copy_idx
          apath   = File.join(tpath,"#{copynum}-#{DB_FNAME}")
          break unless File.exists?(apath)
          copy_idx += 1
        end
        FileUtils.cp Shiftzilla::DB_FPATH, apath
        puts "Backed up the database."
        @db_backed_up = true
      end
    end

    def timestamp
      DateTime.now.to_s
    end

    def bug_url(bug_id)
      return "#{BZ_URL}#{bug_id}"
    end

    def set_axis_increment(initial_value)
      case
      when initial_value < 10
        return 1
      when initial_value < 20
        return 2
      when initial_value < 50
        return 5
      when initial_value < 100
        return 10
      when initial_value < 200
        return 20
      when initial_value < 400
        return 25
      else
        return 100
      end
    end

    def all_bugs_query(snapshot)
      return "SELECT AB.'Bug ID', AB.'Component', AB.'Target Release', AB.'Assignee', AB.'Status', AB.'Summary', AB.'Keywords', AB.'PM Score', AB.'External Bugs' FROM ALL_BUGS AB WHERE AB.'Snapshot' = date('#{snapshot}')"
    end

    def component_bugs_query(components,snapshot)
      rclause = list_clause(components)
      rfilter = rclause == '' ? '' : " AND AB.'Component' #{rclause}"
      return "SELECT AB.'Bug ID', AB.'Component', AB.'Target Release', AB.'Assignee', AB.'Status', AB.'Summary', AB.'Keywords', AB.'PM Score', AB.'External Bugs' FROM ALL_BUGS AB WHERE AB.'Snapshot' = date('#{snapshot}')#{rfilter} ORDER BY AB.'Target Release' DESC"
    end

    def component_bugs_count(components,snapshot)
      rclause = list_clause(components)
      rfilter = rclause == '' ? '' : " AND AB.'Component' #{rclause}"
      return "SELECT count(*) FROM ALL_BUGS AB WHERE AB.'Snapshot' = date('#{snapshot}')#{rfilter}"
    end

    def all_snapshots
      @all_snapshots ||= begin
        all_snapshots = []
        dbh.execute('SELECT DISTINCT Snapshot FROM ALL_BUGS ORDER BY Snapshot ASC') do |row|
          all_snapshots << row[0]
        end
        all_snapshots
      end
    end

    def latest_snapshot
      all_snapshots[-1]
    end

    def field_map
      {
        :assigned_to      => 'Assignee',
        :component        => 'Component',
        :id               => 'Bug ID',
        :keywords         => 'Keywords',
        :cf_pm_score      => 'PM Score',
        :status           => 'Status',
        :summary          => 'Summary',
        :target_release   => 'Target Release',
        :external_bugs    => 'External Bugs',
      }
    end

    private

    def list_clause(list)
      return '' if list.length == 0
      if list.length > 1
        stmt = list.map{ |t| "'#{t}'" }.join(',')
        return "IN (#{stmt})"
      end
      return "== '#{list[0]}'"
    end

    def db_backed_up
      @db_backed_up ||= false
    end

    def valid_config_string?(value)
      return false if value.class == NilClass
      return false if value.class == String and value.length == 0
      return true
    end

    def validated_config_file(raw_cfg)
      unless raw_cfg.class == Hash
        puts "#{CFG_FILE} did not get parsed as a hash."
        exit
      end
      missing_keys = ['OrgTitle','Groups','Teams','Sources','Releases','SSH'].select{ |k| not raw_cfg.has_key?(k) }
      if missing_keys.length > 0
        if missing_keys.length > 1
          puts "#{CFG_FILE} is missing the following keys: #{missing_keys.join(', ')}"
        else
          puts "#{CFG_FILE} is missing the '#{missing_keys[0]}' key."
        end
        exit
      end
      zero_length_lists = ['Groups','Teams','Releases'].select{ |k| not raw_cfg[k].class == Array or raw_cfg[k].length == 0 }
      if zero_length_lists.length > 0
        if zero_length_lists.length > 1
          puts "#{CFG_FILE} contains some zero-length lists: #{zero_length_lists.join(', ')}"
        else
          puts "#{CFG_FILE} contains a zero-length list for #{zero_length_lists[0]}"
        end
        exit
      end

      errors = []

      # OrgTitle check
      if not valid_config_string?(raw_cfg['OrgTitle'])
        errors << "OrgTitle value is nil or zero-length"
      end

      # Group checks
      list_idx  = 0
      seen_gids = {}
      raw_cfg['Groups'].each do |group|
        if not group.has_key?('id')
          errors << "Group at index #{list_idx} is missing the 'id' key."
        elsif not valid_config_string?(group['id'])
          errors << "Group at index #{list_idx} has a nil or zero-length 'id'."
        else
          gid = group['id']
          if seen_gids.has_key?(gid)
            errors << "Group at index #{list_idx} has same id ('#{gid}') as group at index #{seen_gids[gid]}"
          else
            seen_gids[gid] = list_idx
          end
        end
        if not group.has_key?('lead')
          errors << "Group at index #{list_idx} is missing the 'lead' key."
        elsif not valid_config_string?(group['lead'])
          errors << "Group at index #{list_idx} has a nil or zero-length 'lead'."
        end
        list_idx += 1
      end

      # Team checks
      list_idx  = 0
      seen_tnms = {}
      raw_cfg['Teams'].each do |team|
        if not team.has_key?('name')
          errors << "Team at index #{list_idx} is missing the 'name' key."
        elsif not valid_config_string?(team['name'])
          errors << "Team at index #{list_idx} has a nil or zero-length 'name'."
        elsif team['name'].start_with?("Group")
          errors << "Team at index #{list_idx} begins with the string 'Group'."
        else
          tnm = team['name']
          if seen_tnms.has_key?(tnm)
            errors << "Team at index #{list_idx} has same name ('#{tnm}') as team at index #{seen_tnms[tnm]}"
          else
            seen_tnms[tnm] = list_idx
          end
        end
        if not team.has_key?('lead')
          errors << "Team at index #{list_idx} is missing the 'lead' key."
        elsif not valid_config_string?(team['lead'])
          errors << "Team at index #{list_idx} has a nil or zero-length 'lead'."
        end
        if not team.has_key?('group')
          errors << "Team at index #{list_idx} is missing the 'group' key."
        elsif not valid_config_string?(team['group'])
          errors << "Team at index #{list_idx} has a nil or zero-length 'group'."
        elsif not seen_gids.has_key?(team['group'])
          errors << "Team at index #{list_idx} has a group id ('#{team['group']}') that doesn't map to any Group."
        end
        if team.has_key?('components')
          comps = team['components']
          if not comps.class == Array
            errors << "Team at index #{list_idx} has a 'components' key that didn't parse as a list"
          else
            comp_idx = 0
            comps.each do |comp|
              if not valid_config_string?(comp)
                errors << "Team at index #{list_idx} has a nil or zero-length BZ component at index #{comp_idx}"
              end
              comp_idx += 1
            end
          end
        end
        list_idx += 1
      end

      # Release checks
      list_idx  = 0
      seen_rnms = {}
      raw_cfg['Releases'].each do |release|
        if not release.has_key?('name')
          errors << "Release at index #{list_idx} is missing the 'name' key."
        elsif not valid_config_string?(release['name'])
          errors << "Release at index #{list_idx} has a nil or zero-length 'name'."
        else
          rnm = release['name']
          if seen_rnms.has_key?(rnm)
            errors << "Release at index #{list_idx} has same name ('#{rnm}') as release at index #{seen_rnms[rnm]}"
          else
            seen_rnms[rnm] = list_idx
          end
        end
        if not release.has_key?('targets')
          errors << "Release at index #{list_idx} is missing the 'targets' key."
        else
          targets = release['targets']
          if not targets.class == Array
            errors << "Release at index #{list_idx} has a 'targets' key that didn't parse as a list"
          else
            tgt_idx = 0
            targets.each do |tgt|
              if not valid_config_string?(tgt)
                errors << "Release at index #{list_idx} has a nil or zero-length target at index #{tgt_idx}"
              end
              tgt_idx += 1
            end
          end
        end
        if not release.has_key?('milestones')
          errors << "Release at index #{list_idx} is missing the 'milestones' key."
        else
          milestones = release['milestones']
          if not milestones.class == Hash
            errors << "Release at index #{list_idx} has a 'milestones' key that didn't parse as a hash"
          else
            ['start','feature_complete','code_freeze','ga'].each do |ms|
              if not milestones.has_key?(ms)
                errors << "Release at index #{list_idx} is missing the '#{ms}' milestone."
              else
                ms_date = milestones[ms].split('-')
                if ms_date.length == 3 and ms_date[0].length == 4 and ms_date[1].length == 2 and ms_date[2].length == 2
                else
                  errors << "Release at index #{list_idx}: milestone '#{ms}' is not formatted correctly (YYYY-MM-DD)."
                end
              end
            end
          end
        end
        list_idx += 1
      end

      # Source checks
      if not raw_cfg['Sources'].class == Hash
        errors << "The Sources portion of the config file didn't parse as a hash."
      else
        seen_srcs = {}
        raw_cfg['Sources'].each do |src_id,src_info|
          ['search','sharer','table','external_sub','fields'].each do |key|
            if not src_info.has_key?(key)
              errors << "Source '#{src_id}' is missing the '#{key}' key."
            else
              if key == 'fields'
                if not src_info['fields'].class == Array
                  errors << "Source '#{src_id}': the 'fields' value didn't parse as a list."
                else
                  fld_idx = 0
                  src_info['fields'].each do |fld|
                    if not valid_config_string?(fld)
                      errors << "Source '#{src_id}': the field value at index #{fld_idx} is nil or zero-length."
                    end
                    fld_idx += 1
                  end
                end
              elsif not valid_config_string?(src_info[key])
                errors << "Source '#{src_id}' has nil or zero-length value for '#{key}'"
              end
            end
          end
        end
      end

      # SSH checks
      if not raw_cfg['SSH'].class == Hash
        errors << "The SSH portion of the config file didn't parse as a hash."
      else
        ssh = raw_cfg['SSH']
        ['host','path','url'].each do |key|
          if not ssh.has_key?(key)
            errors << "SSH config is missing the '#{key}' key."
          elsif not valid_config_string?(ssh[key])
            errors << "SSH config: '#{key}' value is nil or zero-length"
          end
        end
      end

      # Report errors
      if errors.length > 0
        puts "Config file at '#{CFG_FILE}' has the following errors:"
        errors.each do |error|
          puts "- #{error}"
        end
        exit
      end

      return raw_cfg
    end
  end
end
