# coding: utf-8

require 'open-uri'
require 'uri'

rack_env = ENV['RACK_ENV'] || 'development'
dbconfig = YAML.load(File.read('config/database.yml'))
ActiveRecord::Base.establish_connection dbconfig[rack_env]

MetaWhere.operator_overload!

configure :development do
  Slim::Engine.set_default_options :pretty => true
end

configure :staging do
  use Rack::Auth::Basic do |username, password|
    username == ENV['STAGING_BASIC_AUTH_USERNAME'] && password == ENV['STAGING_BASIC_AUTH_PASSWORD']
  end
end

configure :production do
  set :sass, { :style => :compressed }
end

class Star < ActiveRecord::Base
  validates_uniqueness_of :uri
  validates_presence_of :uri, :title, :color, :star_count

  validates_numericality_of :star_count, :request_count, :api_request_count, :error_count
  validates_numericality_of :static_image_count, :cached_image_count, :create_image_count
end

before do
  @google_analytics_id = ENV['GOOGLE_ANALYTICS_ID']
  @api_uri = 'http://s.hatena.ne.jp/blog.json/'

  default_interval_min = 60
  @update_interval_min = ENV['UPDATE_INTERVAL_MIN'].to_i rescue default_interval_min
  @update_interval_min = default_interval_min if @update_interval_min == 0
  @update_star_count = nil

  # http://b.hatena.ne.jp/help/bcounter
  @colors = %w( de dg gr pr br rd sp pk te lg lb wh bl li or )

  @star  = nil
  @title = nil
  @color = nil
  @error_count   = 0
  @error_message = []
  @static_image_count = 0
  @cached_image_count = 0
  @create_image_count = 0
end

after '/sc/*/*' do
  after_save_record
end

get '/' do
  @stars = Star.where(:request_count > 10).where(:updated_at > 12.hours.ago).order(:star_count.desc).limit(10)

  ua = request.user_agent
  if b = ["MSIE 7.0", "MSIE 6.0", "MSIE 5.0"].find {|s| ua.include?(s) }
    slim :invalid_browser_version
  else
    slim :index
  end
end

# get '/ranking' do
  # @star = Star.where(:created_at > 1.days.ago).order('star_count asc').limit(100)
  # slim :ranking
# end

get '/sc/*/*' do
  @color = @colors.include?(params[:splat][0]) ? params[:splat][0] : @colors.first

  uri = params[:splat][1]
  unless validation_of_uri(uri)
    create_error
    redirect("/counters/#{@color}/____.gif", 301)
  end

  count  = read_star_count(uri)
  banner = read_banner(count, @color)

  content_type 'image/gif'
  banner
end

get '/style.css' do
  sass :style
end

private
def validation_of_uri(uri)
  exp = /^\b((?:https?:\/\/)(?:[^\s()<>]+|\(([^\s()<>]+|(\([^\s()<>]+\)))*\))+(?:\(([^\s()<>]+|(\([^\s()<>]+\)))*\)|[^\s`!()\[\]{};:'".,<>?«»“”‘’]))$/
  return uri =~ exp
end

def read_star_count(uri)
  @star = Star.where('uri = ?', uri)
  return create_star_count(uri) if @star.blank?

  @star = @star.first
  if @star.api_request_at > @update_interval_min.minutes.ago
    return @star.star_count
  else
    return @update_star_count = create_star_count(uri, false)
  end
end

def create_star_count(uri, is_create_record = true)
  begin
    req  = "#{@api_uri}#{uri}"
    json = parse_json(req)
    star_count = json['star_count'].to_i
    @title = json['title']
    create_record(json) if is_create_record && star_count >= 0
  rescue => e
    create_error e
    star_count = -1
  end
  star_count
end

def parse_json(req)
  begin
    str = open(req) do |data|
      data.read
    end
  rescue => e
    create_error e
    return { 'star_count' => -1 }
  end

  begin
    json = JSON.parse(str)
  rescue => e
    create_error e
    return { 'star_count' => -1 }
  end
  json
end

def create_record(json)
  @star = Star.new
  @star.uri = json['uri']
  @star.title = json['title']
  @star.star_count = json['star_count']
  @star.api_request_count = 1
  @star.api_request_at = Time.now
end

def read_banner(star_count, color = @colors.first)
  redirect("/counters/#{color}/____.gif", 301) if star_count < 0
  star_count = 99999999 if star_count > 99999999

  # if 0-999 then redirect to static banner image
  name = '%04d' % star_count.to_i
  path = "./public/counters/#{color}/#{name}.gif"
  if File.exist?(path) && star_count.to_i >= 0 && star_count.to_i <= 999
    @static_image_count = 1
    redirect("/counters/#{color}/#{name}.gif", 301)
  end

  # if remain for tmp folder then view it
  path = "./tmp/#{color}_#{star_count}.gif"
  if File.exist?(path)
    begin
      banner = File.open(path, "rb") {|f| f.read }
      @cached_image_count = 1
      return banner
    rescue => e
      create_error e
    end
  end

  # create banner image
  create_banner(star_count, color)
end

def create_banner(star_count, color = @colors.first)
  begin
    img = Magick::Image.read("./images/base_#{color}.png").first
    img.format = 'gif'
    fill = (color == 'wh') ? '#9c9c9c' : '#ffffff'
    draw = Magick::Draw.new
    draw.annotate(img, 0, 0, 72, 11, star_count.to_s) do
      self.font = 'Verdana-Bold'
      self.fill = fill
      self.align = Magick::RightAlign
      self.stroke = 'transparent'
      self.pointsize = 10
      self.text_antialias = false
      self.kerning = -1
    end
    path = "./tmp/#{color}_#{star_count}.gif"
    img.write(path)
    @create_image_count = 1
    return img.to_blob
  rescue => e
    create_error e
    redirect("/counters/#{color}/____.gif", 301)
  end
end

def create_error(error = nil)
  @error_message.push("#{error.message}   #{error.backtrace}") if error
  @error_count += 1
end

def after_save_record
  return if @star.blank?
  @star.color = @color
  @star.title = @title
  if @update_star_count && @update_star_count >= 0
    @star.star_count = @update_star_count
    @star.api_request_count += 1
    @star.api_request_at = Time.now
  end
  @star.request_count += 1
  @star.static_image_count += @static_image_count
  @star.cached_image_count += @cached_image_count
  @star.create_image_count += @create_image_count
  @star.error_count += @error_count
  unless @error_message.empty?
    @star.error_message = @error_message.to_s
    @star.error_at = Time.now
  end
  @star.save #TODO: save_errors
end

