require "appium_instrumentor/version"
require "appium_instrumentor/helpers"
require "appium_instrumentor/java_keystore"

module AppiumInstrumentor
  def self.instrument(test_server_apk, app_under_test)
    apk_fingerprint = fingerprint_from_apk(app_under_test)
    log "#{app_under_test} was signed with a certificate with fingerprint #{apk_fingerprint}"

    keystores = JavaKeystore.get_keystores
    if keystores.empty?
      puts "No keystores found."
      exit 1
    end
    keystore = keystores.find { |k| k.fingerprint == apk_fingerprint}

    unless keystore
      puts "#{app_under_test} is not signed with any of the available keystores."
      puts "Tried the following keystores:"
      keystores.each do |k|
        puts k.location
      end
      puts ""
      puts "You can resign the app_under_test with #{keystores.first.location} by running:
    appium_instrumentor resign #{app_under_test}"

      puts ""
      puts "Notice that resigning an app_under_test might break some functionality."
      puts "Getting a copy of the certificate used when the app_under_test was built will in general be more reliable."

      exit 1
    end

    test_server_file_name = 'test_servers/appium-uiautomator2-server-debug-androidTest.apk'
    FileUtils.mkdir_p File.dirname(test_server_file_name) unless File.exist? File.dirname(test_server_file_name)

    unsign_apk(test_server_apk)
    test_server_manifest = File.join(File.dirname(__FILE__), 'appium_instrumentor/resources/AndroidManifest.xml')

    Dir.mktmpdir do |workspace_dir|
      Dir.chdir(workspace_dir) do
        FileUtils.cp(test_server_apk, "TestServer.apk")
        FileUtils.cp(test_server_manifest, "AndroidManifest.xml")

        unless system %Q{"#{RbConfig.ruby}" -pi.bak -e "gsub(/#targetPackage#/, '#{package_name(app_under_test)}')" AndroidManifest.xml}
          raise "Could not replace package name in manifest"
        end

        unless system %Q{"#{Calabash::Android::Dependencies.aapt_path}" package -M AndroidManifest.xml  -I "#{Calabash::Android::Dependencies.android_jar_path}" -F dummy.apk}
          raise "Could not create dummy.apk"
        end

        Calabash::Utils.with_silent_zip do
          Zip::File.new("dummy.apk").extract("AndroidManifest.xml","customAndroidManifest.xml")
          Zip::File.open("TestServer.apk") do |zip_file|

            zip_file.remove("AndroidManifest.xml")
            zip_file.add("AndroidManifest.xml", "customAndroidManifest.xml")
          end
        end
      end
      keystore.sign_apk("#{workspace_dir}/TestServer.apk", test_server_file_name)
      begin

      rescue => e
        log e
        raise "Could not sign test server"
      end
    end
    puts "Done signing the test server. Moved it to #{test_server_file_name}"
  end

  def self.unsign_and_resign_apk(apk_path)
    resign_apk(apk_path)
  end
end
