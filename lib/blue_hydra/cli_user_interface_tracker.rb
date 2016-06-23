require 'securerandom'

module BlueHydra
  class CliUserInterfaceTracker
    attr_accessor :runner, :chunk, :attrs, :address, :uuid

    def initialize(run, chnk, attrs, addr)
      @runner = run
      @chunk = chnk
      @attrs = attrs
      @address = addr

      @lpu  = attrs[:le_proximity_uuid].first if attrs[:le_proximity_uuid]
      @lmn  = attrs[:le_major_num].first      if attrs[:le_major_num]
      @lmn2 = attrs[:le_minor_num].first      if attrs[:le_minor_num]

      cui_k = cui_status.keys
      cui_v = cui_status.values

      match1 = cui_v.select{|x|
        x[:address] == @address
      }.first

      if match1
        @uuid = cui_k[cui_v.index(match1)]
      end

      unless @uuid
        match2 = cui_v.select{|x|
          x[:le_proximity_uuid] && x[:le_proximity_uuid] == @lpu &&
          x[:le_major_num]      && x[:le_major_num]      == @lmn &&
          x[:le_minor_num]      && x[:le_minor_num]      == @lmn2
        }.first

        if match2
          @uuid = cui_k[cui_v.index(match2)]
        end
      end

      unless @uuid
        @uuid = SecureRandom.uuid
      end
    end

    def cui_status
      runner.cui_status
    end

    def update_cui_status
      cui_status[@uuid] ||= {created: Time.now.to_i}
      cui_status[@uuid][:lap] = address.split(":")[3,3].join(":") unless cui_status[@uuid][:lap]

      if chunk[0] && chunk[0][0]
        bt_mode = chunk[0][0] =~ /^\s+LE/ ? "le" : "classic"
      end

      if bt_mode == "le"
        if attrs[:lmp_version] && attrs[:lmp_version].first !~ /0x(00|FF|ff)/
          cui_status[@uuid][:vers] = "LE#{attrs[:lmp_version].first.split(" ")[1]}"
        elsif !cui_status[@uuid][:vers]
          cui_status[@uuid][:vers] = "BTLE"
        end
      else
        if attrs[:lmp_version] && attrs[:lmp_version].first !~ /0x(00|ff|FF)/
          cui_status[@uuid][:vers] = "CL#{attrs[:lmp_version].first.split(" ")[1]}"
        elsif !cui_status[@uuid][:vers]
          cui_status[@uuid][:vers] = "CL/BR"
        end
      end

      [
        :last_seen, :name, :address, :classic_rssi, :le_rssi,
        :le_proximity_uuid, :le_major_num, :le_minor_num, :ibeacon_range
      ].each do |key|
        if attrs[key] && attrs[key].first
          if cui_status[@uuid][key] != attrs[key].first
            if key == :le_rssi || key == :classic_rssi
              cui_status[@uuid][:rssi] = attrs[key].first[:rssi].gsub('dBm','')
            elsif key == :ibeacon_range
              cui_status[@uuid][:range] = attrs[key].first
            elsif key == :le_major_num
              cui_status[@uuid][:major] = attrs[key].first
            elsif key == :le_minor_name
              cui_status[@uuid][:minor] = attrs[key].first
            else
              cui_status[@uuid][key] = attrs[key].first
            end
          end
        end
      end

      cui_status[@uuid][:uuid] = @uuid.split('-')[0]
      if attrs[:short_name]
        unless attrs[:short_name] == [nil] || cui_status[@uuid][:name]
          cui_status[@uuid][:name] = attrs[:short_name].first
          BlueHydra.logger.warn("short name found: #{attrs[:short_name]}")
        end
      end

      if attrs[:appearance]
        cui_status[@uuid][:type] = attrs[:appearance].first.split('(').first
      end

      if attrs[:classic_minor_class]
        if attrs[:classic_minor_class].first =~ /Uncategorized/i
          cui_status[@uuid][:type] = "Uncategorized"
        else
          cui_status[@uuid][:type] = attrs[:classic_minor_class].first.split('(').first
        end
      end

      if [nil, "Unknown"].include?(cui_status[@uuid][:manuf])
        if bt_mode == "classic" || (attrs[:le_address_type] && attrs[:le_address_type].first =~ /public/i)
            vendor = Louis.lookup(address)

            cui_status[@uuid][:manuf] = if vendor["short_vendor"]
                                            vendor["short_vendor"]
                                          else
                                            vendor["long_vendor"]
                                          end
        else
          cmp = nil

          if attrs[:company_type] && attrs[:company_type].first !~ /unknown/i
            cmp = attrs[:company_type].first
          elsif attrs[:company] && attrs[:company].first !~ /not assigned/i
            cmp = attrs[:company].first
          elsif attrs[:manufacturer] && attrs[:manufacturer].first !~ /\(65535\)/
            cmp = attrs[:manufacturer].first
          else
            cmp = "Unknown"
          end

          if cmp
            cui_status[@uuid][:manuf] = cmp.split('(').first
          end
        end
      end
    end
  end
end
