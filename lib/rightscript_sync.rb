require 'pp'
require 'stringio'
require 'yaml'
require 'right_api_client'
require 'terminal-table'

class RightscriptUpload < Thor
  class_option :config, desc: 'The path to the configuration file containing the RightScale API credentials',
    aliases: '-c', default: File.expand_path('~/.right_api_client/login.yml')

  desc "list", "List RightScripts"
  method_option :filter, 
    :desc => "Filter names according to regular expression",
    :aliases => "-f"
  def list
    filter_opts = {}
    if options[:filter]
      filter_opts = {
        :filter => ["name==#{options[:filter]}"]
      }
    end
    right_scripts = api_client.right_scripts.index(filter_opts)
    right_scripts.select! {|scr| scr.revision.to_i == 0}
    puts ""
    table = Terminal::Table.new do |t|
      t << ['Name', "HREF"]
      t.add_separator
      right_scripts.each do |rs|
        dash_href = public_href(rs)
        t << [rs.name, dash_href]
      end
    end
    puts table
  end

  desc "upload <files>", "Upload RightScript from file or directory"
  method_option :force,
    :desc => "Force upload of files without metadata",
    :type => :boolean,
    :aliases => "-f"
  def upload(*files)
    file_list = get_file_list(files) 
    failed = verify_file_list(file_list)
    if failed.length > 0
      puts "The following files have no metadata: "
      failed.each { |f| puts f }
      puts 
      if options[:force]
        puts "Force flag is set, uploading all files anyways"
      else
        puts "Please run 'rightscript_sync set_metadata <file or directory>' to add metadata for files"
        puts "Or else pass the --force flag to upload anyways"
        exit 1
      end
    end
    file_list.each do |f|
      push_to_rightscale(f)
    end
  end
  
  desc "set_metadata <files>", "Add metadata to files, if it doesn't exist"
  def set_metadata(*files)
    file_list = get_file_list(files)
    files_no_metadata = verify_file_list(file_list)
    files_no_metadata.each do |file|
      file_no_extension = File.basename(file,File.extname(file))
      insert_metadata(file, file_no_extension)
    end
  end

  desc "download <file> [-n -i] <script dash name>", "Download RightScript to file"
  method_option :id, 
    :desc => "RightScript ID number to download",
    :aliases => "-i",
    :type => :numeric
  method_option :name, 
    :desc => "RightScript Name to download",
    :aliases => "-n"
  def download(file)
    raise ArgumentError.new("Either name or id must be supplied") unless options[:name] || options[:id]
    raise ArgumentError.new("Filename to download to must be supplied") unless file && !file.empty?

    if options[:id]
      rightscript = api_client.right_scripts(:id => options[:id]).show
    elsif options[:name]
      rightscripts = api_client.right_scripts.index(:filter => ["name==#{options[:name]}"])
      rightscripts = rightscripts.select { |rs| rs.revision.to_i == 0 && rs.name == options[:name] }
      if rightscripts.length > 1
        raise ArgumentError.new("More than one rightscript round with name #{options[:name]}")
      elsif rightscripts.length == 0
        raise ArgumentError.new("Could not find rightscript named #{options[:name]}")
      end
      rightscript = rightscripts.first
    end

    script_contents = rightscript.source.show.text
    if file == "-"
      puts script_contents
    else
      File.open(file, "w") do |f|
        puts "Saving RightScript contents to #{file}"
        f.puts(script_contents)
      end
      unless has_metadata?(file)
        insert_metadata(file, rightscript.name, rightscript.description)
      end
    end
  end

  private
  def has_metadata?(filename)
    raise ArgumentError.new("File #{filename} does not exist") unless ::File.exists?(filename)

    File.open(filename) do |file|
      has_metadata = false
      in_metadata = false
      file.each_line do |line|
        if in_metadata
          has_metadata = true if line.start_with?('# ...')
        else
          in_metadata = true if line.start_with?('# ---')
        end
      end
      # puts "The file #{filename} #{has_metadata ? "has" : "does not have"} metadata"
      has_metadata
    end
  end

  def get_metadata(file)
    raise ArgumentError.new("File #{file} does not exist") unless ::File.exists?(file)
    yaml_metadata = nil
    File.open(file) do |file|
      in_metadata = false
      metadata = StringIO.new
      file.each_line do |line|
        if in_metadata
          metadata << line[2 .. -1]
          break if line.start_with?('# ...')
        elsif line.start_with?('# ---')
          metadata << line[2 .. -1]
          in_metadata = true
        end
      end
      metadata.rewind
      yaml_metadata = YAML.load(metadata) || {}
    end
    pp yaml_metadata
    yaml_metadata
  end

  def api_client
    @client ||= RightApi::Client.new(YAML.load_file(options[:config]).merge(timeout: nil))
    @client.log(STDERR)
    @client
  end


  # works for deployment, simple stuff, won't work for everything
  def public_href(rsrc)
    account_id = api_client.instance_variable_get(:@account_id)
    base_url = api_client.instance_variable_get(:@api_url)
    "#{base_url}/acct/#{account_id}/#{rsrc.href.sub('/api/','')}"
  end

  def verify_file_list(files)
    failed = []
    files.each do |file|
      unless has_metadata?(file)
        failed << file
      end
    end
    failed
  end

  def get_file_list(files)
    file_list = []
    files.each do |file|
      raise ArgumentError.new("File #{file} does not exist") unless ::File.exists?(file)
      if File.read(file).split("\n").length == 0
        puts "Skipping #{file}, is empty"
        next
      end
      if ::File.directory?(file)
         puts "Skipping #{file}, it is a directory"
      else
        file_list |= [file]
      end
    end
    file_list
  end

  def insert_metadata(file, name, description = "")
    metadata_lines    = [
      "# ---",
      "# RightScript Name: #{name}",
      "# Description: #{description}",
      "# Packages: ",
      "# ...",
      "# "
    ]
    file_lines = File.read(file).split("\n")
    if file_lines.length > 0 && file_lines.first.include?("#!")
      file_lines.insert(1, "", metadata_lines)
    else
      file_lines.insert(0, metadata_lines)
    end
    File.open(file, "w") do |f|
      puts "Saving file #{file}"
      f.puts(file_lines.join("\n"))
    end
  end

  def list_files(dir, filter = "*")
    Dir.glob(File.expand_path("#{dir}/##{filter}")).each do |file| 
      puts file
    end
  end

  def push_to_rightscale(file)
    if has_metadata?(file)
      metadata = get_metadata(file)
      name = metadata["RightScript Name"]
      description = metadata["Description"]
    else
      name = File.basename(file,File.extname(file))
      description = nil
    end
    rightscripts = api_client.right_scripts.index(:filter => ["name==#{name}"])
    rightscripts = rightscripts.select { |rs| rs.revision.to_i == 0 && rs.name == name }
    if rightscripts.length > 1
      puts "WARNING: Cannot upload #{name}, multiple rightscripts match"
      return
    end
    if rightscripts.length == 1
      rs = rightscripts.first.show
      puts "Pushing #{file} up to RightScale with RightScript name #{name} and href #{public_href(rs)}"
      rs.update(right_script: {description: description, source: File.read(file)})
    else
      puts "Creating RightScript '#{name}'"
      api_client.right_scripts.create(right_script: {name: name, source: File.read(file)})
    end
  end

  def get_from_rightcale( script_name )
    puts "Get #{script_name} from RightScale"
  end 
end

