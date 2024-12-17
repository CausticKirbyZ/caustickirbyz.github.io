require "cmark"
require "http/server"
require "ecr"
require "option_parser"
require "tallboy"
require "crinja"
require "yaml"



def get_metadata(file : String ) : Hash(YAML::Any,YAML::Any)?
  
  if File.exists?(file)
    filemd = File.read(file)
      
    if match = filemd.match(/^---\n(.*?)\n---\n(.*)/m)
      # Extract the front matter and content
      yaml_part = match[1]
      content_part = match[2]

      # Parse the YAML part into a Hash
      front_matter_data = YAML.parse(yaml_part).as_h
      filemd = content_part
      return front_matter_data
    else
      # no front matter  
    end 
  else 
    return nil 
  end

end 




def dirtree(folder : String) : Array(NamedTuple(name: String, path: String))
  files = [] of NamedTuple(name: String, path: String)
  # puts "Folder: #{folder}"
  Dir.entries(folder).map do |file|
    next if (file == "." || file == "..")

    if Dir.exists? "#{folder}/#{file}"
      dirtree("#{folder}/#{file}".gsub("//", "/")).each do |f|
        files << f
      end
    end

    if file.ends_with? ".md"
      files << {name: file, path: "#{folder}/#{file}".gsub("//", "/")}
      puts "File: #{file}"
      puts "    : #{get_metadata("#{folder}/#{file}".gsub("//", "/"))}"
    end
  end

  return files
end







def start_dev_server(folder : String)

  options = Cmark::Option.flags(
    # Nobreaks,
    # ValidateUTF8,
    # LiberalHTMLTag,
    # Unsafe,                                            # this will put raw html in the output
    # Footnotes  
  
    ValidateUTF8,
    Smart,
    GithubPreLang,
    LiberalHTMLTag,
    Footnotes,
    StrikethroughDoubleTilde,
    TablePreferStyleAttributes,
    FullInfoString



    
  )                                       # deafult is Option::None
  extensions = Cmark::Extension.flags(
    # Table, Tasklist


    Table,
    Strikethrough,
    Autolink,
    Tagfilter,
    Tasklist
  ) # default is Extension::None

  server = HTTP::Server.new do |context|
    context.response.content_type = "text/html"

    req_path = URI.decode( context.request.path.to_s )
    highlighted_langs = [] of String 
    page_title = ""
    front_matter_data = "" 
    date_str = "" 
    
    
      if req_path.matches? /\/styles\/.*\.css/i
      context.response.content_type = "text/css"
      path = req_path.split("/")[2..].join("/")
      context.response.print File.read("#{folder}/styles/#{path}")
      next
    elsif req_path.matches? /^\/images\/.*\.(png|jpg|jpeg|gif)/i      
      context.response.content_type = "image/png image/jpeg image/jpg image/gif"
      path = context.request.path.split("/")[2..].join("/")
      context.response.print File.read("#{folder}/images/#{path}")
      next
    elsif req_path.matches? /^\/content\/images\/.*\.(png|jpg|jpeg|gif)/i

      context.response.content_type = "image/png image/jpeg image/jpg image/gif"
      path = context.request.path.split("/")[2..].join("/").gsub("//", "/")
      puts path 
      context.response.print File.read("#{folder}/content/#{path}")
      next
    elsif req_path == "/" 
      if File.exists?("#{folder}/index.md")        
        filemd = File.read("#{folder}/index.md")


        if match = filemd.match(/^---\n(.*?)\n---\n(.*)/m)
          # Extract the front matter and content
          yaml_part = match[1]
          content_part = match[2]
      
          # Parse the YAML part into a Hash
          front_matter_data = YAML.parse(yaml_part).as_h
          filemd = content_part 
          pp front_matter_data
        else
          # no front matter  
        end 


        dfiles = dirtree("#{folder}/content/")
        table = Tallboy.table(border: :none) do
          header ["Name", "Path"]
          dfiles.each do |f|
            row [
              "[#{f[:name]}](#{URI.encode_path(f[:path].gsub(folder, "").rstrip(".md")) })", f[:path]
          ]
          end
        end
        indexpage = Crinja.render(filemd, {"directoryfiles" => table.render(:markdown).to_s})
        content = Cmark.document_to_html(indexpage, options, extensions)
      else 
        context.response.status_code = 404
        content = ".... LOL someone forgot to create a whoami.md file?"
      end 
      context.response.print ECR.render "./src/index.ecr"
      next




      #   now we append directory content to the home page
      #   files = Dir.entries(folder).map do |file|
      #     if file.ends_with? ".md"
      #       {name: file, path: file}
      #     end
      #   end
      #   content = ECR.def_to_s  "./src/index.ecr"

      context.response.print ECR.render "./src/index.ecr"
      next
    
    elsif req_path == "/whoami"
      if File.exists?("#{folder}/whoami.md")         
        filemd = File.read("#{folder}/whoami.md")
        content = Cmark.document_to_html(filemd, options, extensions)
      else 
        context.response.status_code = 404
        content = ".... LOL someone forgot to create a whoami.md file?"
      end 
      context.response.print ECR.render "./src/index.ecr"
      next

    elsif ( req_path == "/favicon.ico" || req_path == "/images/favicon.ico" ) 
      context.response.content_type = "image/x-icon"
      context.response.print File.read("#{folder}/images/favicon.ico")

      next



    else
      filemd = File.read("#{folder}/#{req_path}.md")
      if filemd.nil?
        context.response.status_code = 404
        context.response.print "Error: 404 Page Does Not Exist"
        next
      end

      if match = filemd.match(/^---\n(.*?)\n---\n(.*)/m)
        # Extract the front matter and content
        yaml_part = match[1]
        content_part = match[2]
    
        # Parse the YAML part into a Hash
        front_matter_data = YAML.parse(yaml_part).as_h
        filemd = content_part 
        pp front_matter_data
      else
        # no front matter  
      end 


      begin 
        date_str = Time.parse_utc(front_matter_data["date"].to_s, "%F" ).to_s("%B %-d, %Y")
      rescue 
      end 
      # page_title = filemd.split("\n")[0].gsub("#", "").strip
      page_title = req_path.split("/").last.titleize

      
      highlighted_langs = filemd.scan(/```(\w+)/).map { |m| m[0].strip("`") }.uniq


      content = Cmark.document_to_html(filemd, options, extensions)


      
      context.response.print ECR.render "./src/index.ecr"
      next
    end
  end

  address = server.bind_tcp "0.0.0.0", 8900
  puts "Listening on http://#{address}"
  server.listen
end

OptionParser.parse do |parser|
  parser.banner = "Usage: site_gen [options]"

  parser.on("-i", "--input FILE", "Input markdown file") do |file|
    # puts markdown_to_html(file)
    #
  end

  parser.on("-h", "--help", "Prints this help") do
    puts parser
  end

  parser.on("--serve [folder-path]", "Starts the server hosting the directory at folder-path") do |folderpath|
    puts "Starting the server..."
    start_dev_server(folderpath)
  end

  parser.invalid_option do |flag|
    STDERR.puts "ERROR: #{flag} is not a valid option."
    STDERR.puts parser
    exit(1)
  end
end
