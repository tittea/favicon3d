# -*- coding: utf-8 -*-
# require 'haml'
#gem 'sinatra'#, '= 1.0'
require 'sinatra'
require 'sinatra/base'
#require 'config/database'
require 'haml'
require 'sass'
require 'rubygems'
require 'RMagick'
require 'net/http'
require 'uri'
require 'digest/sha2'
require 'aws/s3'
require 'right_aws'

require 'sinatra/reloader' if development?

AWS_ID = ENV['AWS_ID']
AWS_KEY = ENV['AWS_KEY']

include AWS::S3

enable :sessions
set :haml, {:format => :html5 }
set :root, File.dirname(__FILE__)
set :public, Proc.new { File.join(root, "public") }

helpers do
  def link_to text, url=nil
    haml "%a{:href => '#{ url || text }'} #{ text }"
  end

  def link_to_unless_current text, url=nil
    if url == request.path_info
      text
    else
      link_to text, url
    end
  end
end

# SASS stylesheet
get '/style.css' do
  headers 'Content-Type' => 'text/css; charset=utf-8'
  sass :style
end

error do
  env['sinatra.error'].name+':error occurs. Did you enter the favicon url?'
end

get '/' do
  @imagefiles = []
  @imagefiles,@orgurls = recentImageS3()

  @convert_file = "sample_takora.png"

  @s3filename  = session[:s3filename] 
  haml :index, :layout => :'layouts/default'
end

get '/about' do
  haml :about, :layout => :'layouts/default'
end

post '/convert' do
  faviconurl = params[:url]
  #get favicon from url
  begin
    faviconfile = save_favicon(faviconurl) 
  rescue
    raise "error URL maybe invalid.."
  end
  
  if faviconfile == false then
    "fail"
  end

  p faviconfile 
  #check favicon filetype
  #check favicoon size is 16x16?
  #convert to 3D
  @convert_file = favicon3D(faviconfile,faviconurl)
  #upload to amazon S3
  p @convert_file
  uploadtoS3(@convert_file)
  #redirect to top page with convertd image url

  @imagefiles,@orgurls = recentImageS3()

  @s3filename = File::basename(@convert_file)

  #put sdb
  sdb = RightAws::SdbInterface.new(AWS_ID,AWS_KEY)
  attr = {}
  attr['s3filename'] = @s3filename
  attr['createdon'] = Time.now.utc.iso8601
  sdb.put_attributes 'favicon3d', URI.escape(faviconurl), attr #@todo error handling

  session[:s3filename] = @s3filename
  redirect '/#article2';
  #haml :index,:layout => :'layouts/default'
end

get "/user/:id" do
  "You're looking for user with id #{ params[:id] }"
end


private
def recentImageS3
  filenames = []
  orgurls = []

  #get recent files
  sdb = RightAws::SdbInterface.new(AWS_ID,AWS_KEY)

  #query = 'select * from favicon3d order by createdon'
  query = 'select * from favicon3d where createdon < \'2013\' order by createdon desc limit 22'
  p query
  result = sdb.select(query) 
  items = result[:items]

  p items

  items.each{|i|
    i.each{|k,v|
      orgurls << k
      filenames << v['s3filename'][-1]
    }
  }
  return filenames,orgurls
end

def uploadtoS3(filename)
  Base.establish_connection!(
                             :access_key_id => AWS_ID
                             :secret_access_key => AWS_KEY)
  p filename
  File.open(filename,'rb') do |f|
    S3Object.store('/img/'+File::basename(filename),f,'favicon3d',:access=>:public_read)
  end

end

def favicon3D(filename,url)
  newfilename = File::dirname(filename)+'/'+File::basename(filename,'.*')+'_3d'+'.png'
  p 'pathpath'
  p newfilename
  imglst = Magick::ImageList.new()

  image = Magick::Image.read(filename).first
  orgimg = image.dup

  #x10
  image.sample!(10)
  image.background_color = "#ffffff"

  #degree radius
  deg = 15
  rad = Math::PI*2*deg/360

  #shear
  shearimage = image.shear(0,deg)

  #right top
  shadowimage_top = Magick::Image.new(230,230)

  shadow_top = Magick::Draw.new

  shadowimage_top.background_color = Magick::Pixel.new(255,255,255,Magick::MaxRGB)

  #draw shadow
  16.downto(1).each{|r|
    1.upto(16).each{|c|
      pixel = orgimg.get_pixels(c-1,r-1,1,1).first

      if pixel.opacity < 65535 then #if transparent, ignore
        x = c*10+20
        y = r*10
        x2 = x+10
        y2 = y
        
        x3 = (c+1)*10
        y3 = (r+1)*10
        
        #top
        shadowpixel = pixel
        shadowpixel.red = (pixel.red*0.9) 
        shadowpixel.green = (pixel.green*0.9) 
        shadowpixel.blue = (pixel.blue*0.9) 
        shadow_top.fill(shadowpixel.to_color)
        shadow_top.polygon(x+2,y+Math.tan(rad)*x,
                           x+8, y+Math.tan(rad)*x-7,
                           (x+10)+8, 	y+Math.tan(rad)*(x+10)-7,
                           (x+10)+2,	y+Math.tan(rad)*(x+10))

        #face
        shadowpixel.red = (pixel.red*1.1) 
        shadowpixel.green = (pixel.green*1.1) 
        shadowpixel.blue = (pixel.blue*1.1) 
        shadow_top.fill(shadowpixel.to_color)
        shadow_top.fill(pixel.to_color)
        shadow_top.polygon(x+2,y+Math.tan(rad)*x,
                           x2,y+Math.tan(rad)*x2,
                           x2,y+Math.tan(rad)*x2+9,
                           x+2,y+Math.tan(rad)*x+9)

        #right
        shadowpixel.red = (pixel.red*0.8) 
        shadowpixel.green = (pixel.green*0.8) 
        shadowpixel.blue = (pixel.blue*0.8) 
        shadow_top.fill(shadowpixel.to_color)
        shadow_top.polygon(x2+1,		y+Math.tan(rad)*x2,
                           x2+8,y+Math.tan(rad)*(x2)-10+3,
                           x2+8,y+Math.tan(rad)*(x2)-10+3+9,
                           x2+1,		y+Math.tan(rad)*x2+9)
      end
    }
  }

  #draw
  shadow_top.draw(shadowimage_top)

  #add image list
  imglst << shadowimage_top

  #merge layers
  result = imglst.flatten_images
  
  result[:Caption] = "\n"+url
  result = result.polaroid(0) do
    self.font_weight = Magick::NormalWeight
    self.font_style = Magick::NormalStyle
    self.gravity = Magick::CenterGravity
    self.border_color = "#f0f0f8"
  end    


  # Composite it on a white background so the result is opaque.
  background = Magick::Image.new(result.columns,result.rows)
  result = background.composite(result, Magick::CenterGravity, Magick::OverCompositeOp)

  result = result.composite(orgimg, 115,240, Magick::OverCompositeOp)

  result.write(newfilename)
  return newfilename
end

def save_favicon(url)
  # 画像の content_type と拡張子の対応関係 (ここにない content_type の画像を受け取ると例外発生)
  content_type_table = {
    'image/jpeg' => '.jpg',
    'image/png'  => '.png',
    'image/gif'  => '.gif',
    'image/x-icon'  => '.ico',
    'image/vnd.microsoft.icon' => '.ico'
  }
  ##
  # 指定した URI の画像を取得してファイルに出力する
  # 
  # @param uri_str 取得する画像の URI (String)
  # @param file_name 取得した画像を保存する際のファイル名 (String / 拡張子とドットを除く)
  # @param output_dir 取得した画像を出力する先のディレクトリ. 'icons' など (String)
  # @param content_type_table 取得した画像の content_type と拡張子の関係を表すハッシュ
  #uri_str = 'http://favicon.hatena.ne.jp/?url='+URI.encode(url)
  uri_str = URI.encode(url)
  p File::basename(uri_str,'.*')
  p uri_str

  randstr = ('A'..'Z').to_a + ('0'..'9').to_a
  file_name = File::basename(uri_str,'.*').sub('.','__').sub('/','')+randstr[rand(randstr.size)]+randstr[rand(randstr.size)]
  output_dir = '/tmp/'

  uri = URI.parse( uri_str )
  req = Net::HTTP::Get.new( uri_str )
  res = Net::HTTP.new( uri.host, uri.port ).request( req )
  if res.code == '200'
    ext_str = content_type_table[ res.content_type ]

    if ext_str.nil? then #try to get default favicon
      uri_str = 'http://favicon.hatena.ne.jp/?url='+URI.encode(url)
      p 'try get default'
      p uri_str
      uri = URI.parse( uri_str )
      req = Net::HTTP::Get.new( uri_str )
      res = Net::HTTP.new( uri.host, uri.port ).request( req )
      if res.code == '200' then
        #
      else
        raise "unexpected response code (image server): #{res.code}" 
      end
    end
    # ファイルに出力する
    File.open( "#{output_dir}/#{file_name}#{ext_str}", 'wb' ) do |f|
      f.flock( File::LOCK_EX )
      f << res.body
      f.flock( File::LOCK_UN )
    end
    return "#{output_dir}/#{file_name}#{ext_str}"
  else
    # 画像取得に失敗
    if ext_str.nil? then raise "unexpected response code (image server): #{res.code}" end
  end
end

