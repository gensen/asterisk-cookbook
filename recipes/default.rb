#
# Cookbook Name:: asterisk
# Recipe:: default
#
# Copyright 2011, Chris Peplin
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

case node['platform']
when "ubuntu","debian"
  if node['platform_version'].to_f < 12.04
    apt_repository "asterisk" do
      uri "http://packages.asterisk.org/deb"
      distribution node['lsb']['codename']
      components ["main"]
      keyserver "subkeys.pgp.net"
      key "175E41DF"
    end
  end
end

packages = case node["platform"]
when "ubuntu","debian"
  %w{asterisk-1.8 asterisk-dahdi}
when "arch"
  # Install from the AUR
  []
end

packages.each do |pkg|
  package pkg
end

# Add UFW firewall application, if Ubuntu
file "/etc/ufw/applications.d/asterisk" do
  content "[Asterisk]\ntitle=Asterisk\ndescription=An open-source PBX\nports=5060/udp|10000:20000/udp|69/udp|2000/tcp\n"
  mode "644"
  owner "root"
end

asterisk_service_name = case node["platform"]
when "ubuntu","debian"
  "asterisk-1.8"
when "arch"
  "asterisk"
end

service "asterisk" do
  service_name asterisk_service_name
  supports :restart => true, :reload => true, :status => :true, :debug => :true,
    "logger-reload" => true, "extensions-reload" => true,
    "restart-convenient" => true, "force-reload" => true
end

external_ip = ""
if node["asterisk"].has_key?("public_ipv4")
  external_ip = node["asterisk"]["public_ipv4"]
else
  external_ip = node["ec2"] ? node["ec2"]["public_ipv4"] : node["ipaddress"]
end
users = search(:asterisk)
auth = search(:auth, "id:google")

page_devices = []

users.each do |user|
  if user[:phone_mac]
    template "#{node["tftp"]["directory"]}/SEP#{user[:phone_mac]}.cnf.xml" do
      source "sep.cnf.xml.erb"
      owner "asterisk"
      group "asterisk"
      mode 0644
      variables(:user => user,
                :server_ip_address => node["asterisk"]["internal_ip"],
                :firmware_version => node["asterisk"]["firmware_version"])
    end
  end

  page_devices << "SCCP/#{user[:extension]}/aa=1w"
end

%w{sip meetme voicemail sla manager modules extensions gtalk jabber sccp}.each do |template_file|
  template "/etc/asterisk/#{template_file}.conf" do
    source "#{template_file}.conf.erb"
    owner "asterisk"
    group "asterisk"
    mode 0644
    variables(:external_ip => external_ip,
              :internal_ip => node["asterisk"]["internal_ip"],
              :users => users,
              :operator_extension => node["asterisk"]["operator"],
              :page_devices => page_devices,
              :rooms => node["asterisk"]["meetme_rooms"],
              :auth => auth[0],
              :sip_providers => node["asterisk"]["sip_providers"])
    notifies :reload, resources(:service => "asterisk")
  end
end
