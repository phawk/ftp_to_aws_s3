require 'aws-sdk-v1'
require 'dotenv'
require 'net/ftp'
require 'net/ftp/list'
require 'tempfile'

Dotenv.load

AWS.config(access_key_id: ENV['AWS_ACCESS_KEY_ID'], secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'], region: ENV['AWS_REGION'])

s3 = AWS::S3.new
bucket = s3.buckets[ENV['AWS_S3_BUCKET']]

Net::FTP.open(ENV['FTP_SERVER'], ENV['FTP_USER'], ENV['FTP_PASSWORD']) do |ftp|
  ftp.chdir(ENV['FTP_DIR'])

  ftp.list("**/*") do |e|
    entry = Net::FTP::List.parse(e)

    # Ignore everything that's not a file (so symlinks, directories and devices etc.)
    next unless entry.file?

    # If entry isn't entry.unknown? then there is a bug in Net::FTP::List if this isn't the
    # same name as ftp.nlist('/some/path') would have returned.
    # Format the entry showing its file size and modification time
    # puts "#{entry.basename}, #{entry.filesize}, #{entry.mtime}"

    s3_path = entry.basename

    puts "Checking bucket for '#{s3_path}'"

    if bucket.objects[s3_path].exists?
      puts "Skipping, #{entry.basename} exists on S3"
    else
      puts "Downloading #{entry.basename}"
      temp = Tempfile.new
      temp.binmode # use binary mode

      ftp.getbinaryfile(entry.basename, temp.path)
      puts "Downloaded from FTP"
      obj = bucket.objects[s3_path].write(File.open(temp.path, "rb"))
      puts "Uploaded to S3"
      obj.acl = :public_read
      puts "Uploaded and set ACL for #{obj.key}"

      temp.close
      temp.unlink if File.exists?(temp.path)
    end
  end
end
