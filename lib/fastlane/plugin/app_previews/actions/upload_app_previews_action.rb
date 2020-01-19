require 'fastlane/action'
require 'spaceship'
require 'json'
require 'fileutils'
require_relative '../helper/upload_app_previews_helper'

module Fastlane
  module Actions
    class UploadAppPreviewsAction < Action
      def self.run(params)
        previews_path = params[:previews_path]
        skip_langs = params[:skip_langs].split(',')
        regenerate_posters = params[:regenerate_posters]
        UI.message("Collecting videos and generating posters")
        UI.message("\tPreviews path: #{previews_path}")
        UI.message("\tSkip langs: #{skip_langs}")
        UI.message("\tRegenerate posters: #{regenerate_posters}")

        # Collecting videos and generating posters
        videos = find_previews(previews_path, skip_langs)
        generate_posters(videos, regenerate_posters)

        # Upload videos to the App Store Connect
        options = {}
        options[:username] ||= CredentialsManager::AppfileConfig.try_fetch_value(:apple_id)
        options[:app_identifier] ||= CredentialsManager::AppfileConfig.try_fetch_value(:app_identifier)

        upload_videos(videos, options)
      end

      def self.find_previews(previews_path, skip_langs=[], recreate_posters=false)
        all_langs = [
          "da","de-DE","el","en-AU","en-CA","en-GB","en-US","es-ES","es-MX","fi","fr-CA","fr-FR","id","it",
          "ja","ko","ms","nl-NL","no","pt-BR","pt-PT","ru","sv","th","tr","vi","zh-Hans","zh-Hant"
        ]
        videos = []

        UI.message "Scanning directory: #{previews_path}"
        all_langs.each do |lang|
          lang_path = File.join(previews_path, lang)
          if File.directory?(lang_path)
            if skip_langs.include?(lang)
              UI.message "Skipping lang: #{lang}"
              next
            end

            UI.message "Lang dir found: #{lang_path}"
            
            Dir.glob(File.join(lang_path, "*.{mp4,mov}")).sort.each do |video_path|
              video_filename = File.basename(video_path)
              video_name = File.basename(video_path, File.extname(video_path))
              conf_path = File.join(lang_path, video_name + ".json")
              poster_path = File.join(lang_path, video_name + ".jpg")

              if File.file?(conf_path)
                UI.message "Video found: #{video_path}"
                
                begin
                  conf = JSON.load(File.new(conf_path))

                  videos.push({
                    device_type: conf["device"],
                    timestamp: conf["timestamp"],
                    order: conf["order"],
                    lang: lang,
                    video_path: video_path,
                    poster_path: poster_path
                  })
                rescue
                  UI.important "Invalid video configuration: #{conf_path}"
                end
              else
                UI.important "Missing configuration for video: #{video_filename}"
              end
            end
          end
        end

        return videos
      end

      def self.generate_posters(videos, force=false)
        videos.each do |video|
          poster_path = video[:poster_path]
          if not File.file?(poster_path) or force
            video_path = video[:video_path]
            timestamp = video[:timestamp]
            device = video[:device_type]

            raise "Invalid timestamp #{timestamp}" if (timestamp =~ /^[0-9][0-9].[0-9][0-9]$/).nil?

            is_portrait = Spaceship::Utilities.portrait?(video_path)
            video_resolution = Spaceship::TunesClient.video_preview_resolution_for(device, is_portrait)
            poster = Spaceship::Utilities::grab_video_preview(video_path, timestamp, video_resolution)
            FileUtils.mv(poster.path, poster_path)
            UI.success "Generated poster: #{poster_path}"
          end
        end
      end

      def self.upload_videos(videos, options)
        UI.message("Login to iTunes Connect (#{options[:username]})")
        Spaceship::Tunes.login(options[:username])
        Spaceship::Tunes.select_team
        UI.message("Login successful")

        app = Spaceship::Tunes::Application.find(options[:app_identifier])
        options[:app] = app
            
        details = app.details
        ver = app.edit_version(platform: options[:platform])

        # Video upload
        UI.message("Uploading videos")
        prev_lang = nil
        uploaded_videos = 0
        videos.each do |video|
          if prev_lang != nil and prev_lang != video[:lang] 
            UI.success "Completed lang #{prev_lang}"
            ver.save!
            ver = app.edit_version(platform: options[:platform])
          end

          UI.message "Uploading app preview #{video[:video_path]} for lang #{video[:lang]}..."
          ver.upload_trailer!(video[:video_path], video[:order], video[:lang], video[:device_type], video[:timestamp], video[:poster_path])
          uploaded_videos += 1
          UI.success "Done uploading app preview"

          prev_lang = video[:lang]
        end

        UI.message "Final save"
        ver.save!
        UI.message("Uploaded #{uploaded_videos} videos")

        return uploaded_videos
      end

      def self.description
        "Upload app previews to the App Store Connect"
      end

      def self.authors
        ["Fausto"]
      end

      def self.return_value
        # If your method provides a return value, you can describe here what it does
      end

      def self.details
        # Optional:
        "Automatically upload app previews to the App Store Connect for multiple languages and multiple devices"
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :previews_path,
                                  env_name: "UPLOAD_APP_PREVIEWS_PREVIEWS_PATH",
                               description: "Root path where app previews are stored",
                                  optional: false,
                                      type: String)
                                      
          FastlaneCore::ConfigItem.new(key: :skip_langs,
                                      env_name: "UPLOAD_APP_PREVIEWS_SKIP_LANGS",
                                   description: "An optional list of lang codes (comma separated) to skip",
                                      optional: true,
                                          type: String
                                 default_value: "")
                                      
          FastlaneCore::ConfigItem.new(key: :regenerate_posters,
                                      env_name: "UPLOAD_APP_PREVIEWS_REGENERATE_POSTERS",
                                    description: "Force regenerate video poster images even if already present",
                                      optional: true,
                                          type: Boolean,
                                 default_value: false)
        ]
      end

      def self.is_supported?(platform)
        # Adjust this if your plugin only works for a particular platform (iOS vs. Android, for example)
        # See: https://docs.fastlane.tools/advanced/#control-configuration-by-lane-and-by-platform
        
        [:ios, :android].include?(platform)
      end
    end
  end
end
