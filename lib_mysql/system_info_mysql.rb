# lib_mysql/system_info_mysql.rb
module SystemInfoMySQL
  def self.get_disk_type
    case RUBY_PLATFORM
    when /linux/
      # Tenta detectar SSD usando lsblk ou /sys/block/*/queue/rotational
      # Não é 100% infalível, mas é um bom ponto de partida
      output = `lsblk -d -o NAME,ROTA`
      if output.include?("0") # 0 indica SSD (não rotacional)
        return "SSD"
      end
      # Fallback para verificar arquivos /sys/block/*/queue/rotational
      Dir.glob('/sys/block/*/queue/rotational').each do |file|
        if File.exist?(file) && File.read(file).strip == '0'
          return "SSD"
        end
      end
      return "HDD" # Assume HDD se não encontrar evidência de SSD
    when /darwin/
      # macOS: mais difícil de determinar programaticamente o tipo de disco
      # Assume SSD para a maioria dos Macs modernos
      return "SSD" # Placeholder, ajustar conforme a necessidade
    when /mswin|mingw|cygwin/
      # Windows: Requer comandos específicos ou WMI
      return "Unknown" # Placeholder
    else
      return "Unknown"
    end
  rescue => e
    "Erro ao detectar tipo de disco: #{e.message}"
  end

  def self.get_ram_info
    ram_info = { total: "Erro", free: "Erro", total_mb: 0 }
    case RUBY_PLATFORM
    when /linux/
      meminfo = File.read('/proc/meminfo')
      total_line = meminfo.match(/MemTotal:\s+(\d+)\s+kB/)
      free_line = meminfo.match(/MemAvailable:\s+(\d+)\s+kB/) # MemAvailable é melhor que MemFree
      if total_line && free_line
        total_kb = total_line[1].to_i
        free_kb = free_line[1].to_i
        ram_info[:total] = "#{total_kb / (1024 * 1024.0).round(2)} GB"
        ram_info[:free] = "#{free_kb / (1024 * 1024.0).round(2)} GB"
        ram_info[:total_mb] = total_kb / 1024.0 # Em MB para cálculos
      end
    when /darwin/
      total_bytes = `sysctl -n hw.memsize`.to_i
      total_gb = total_bytes / (1024.0**3)
      ram_info[:total] = "#{total_gb.round(2)} GB"
      ram_info[:total_mb] = total_bytes / (1024.0**2)
      # Memória livre é mais complexa no macOS, pode precisar de 'vm_stat'
      # Por simplicidade, não estamos calculando free RAM aqui para macOS
      ram_info[:free] = "N/A"
    when /mswin|mingw|cygwin/
      # Windows: Usar 'wmic ComputerSystem get TotalPhysicalMemory'
      total_bytes = `wmic ComputerSystem get TotalPhysicalMemory /value`.match(/TotalPhysicalMemory=(\d+)/)&.[](1).to_i
      total_gb = total_bytes / (1024.0**3)
      ram_info[:total] = "#{total_gb.round(2)} GB"
      ram_info[:total_mb] = total_bytes / (1024.0**2)
      ram_info[:free] = "N/A"
    end
    ram_info
  rescue => e
    { total: "Erro", free: "Erro", total_mb: 0, error: e.message }
  end

  def self.get_swap_info
    swap_info = { total: "Erro", free: "Erro" }
    case RUBY_PLATFORM
    when /linux/
      meminfo = File.read('/proc/meminfo')
      total_line = meminfo.match(/SwapTotal:\s+(\d+)\s+kB/)
      free_line = meminfo.match(/SwapFree:\s+(\d+)\s+kB/)
      if total_line && free_line
        total_kb = total_line[1].to_i
        free_kb = free_line[1].to_i
        swap_info[:total] = "#{total_kb / (1024 * 1024.0).round(2)} GB"
        swap_info[:free] = "#{free_kb / (1024 * 1024.0).round(2)} GB"
      end
    when /darwin/
      # macOS: sysctl vm.swapusage
      swap_usage = `sysctl -n vm.swapusage`
      if swap_usage =~ /total = (\d+\.\d+)M +used = (\d+\.\d+)M +free = (\d+\.\d+)M/
        swap_info[:total] = "#{$1.to_f / 1024.0} GB"
        swap_info[:free] = "#{$3.to_f / 1024.0} GB"
      end
    when /mswin|mingw|cygwin/
      # Windows: wmic OS get TotalSwapSpaceSize, FreeSwapSpaceSize
      total_kb = `wmic OS get TotalSwapSpaceSize /value`.match(/TotalSwapSpaceSize=(\d+)/)&.[](1).to_i
      free_kb = `wmic OS get FreeSwapSpaceSize /value`.match(/FreeSwapSpaceSize=(\d+)/)&.[](1).to_i
      if total_kb > 0
        swap_info[:total] = "#{(total_kb / (1024 * 1024.0)).round(2)} GB"
        swap_info[:free] = "#{(free_kb / (1024 * 1024.0)).round(2)} GB"
      end
    end
    swap_info
  rescue => e
    { total: "Erro", free: "Erro", error: e.message }
  end

  def self.get_cpu_cores
    case RUBY_PLATFORM
    when /linux/
      output = `nproc --all 2>/dev/null`
      output.to_i > 0 ? output.to_i : File.read('/proc/cpuinfo').scan(/^processor\s*:/).count
    when /darwin/
      `sysctl -n hw.ncpu`.to_i
    when /mswin|mingw|cygwin/
      `WMIC CPU Get NumberOfCores /value`.match(/NumberOfCores=(\d+)/)&.[](1).to_i
    else
      1 # Default para 1 se não puder determinar
    end
  rescue => e
    "Erro ao obter núcleos da CPU: #{e.message}"
  end
end