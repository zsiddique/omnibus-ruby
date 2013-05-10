#
# Copyright:: Copyright (c) 2012 Opscode, Inc.
# License:: Apache License, Version 2.0
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

require 'omnibus/artifact_collection'
require 'spec_helper'


describe Omnibus::ArtifactCollection do

  # project_json is the thing that maps a build to. It is stored in the same
  # directory with basename determined by project, e.g., "chef.json" for
  # chef-client, "chef-server.json" for chef-server. By convention, the first
  # entry is the platform that we actually do the build on.
  let(:platform_map_json) do
    <<-E
{
  "build_os=centos-5,machine_architecture=x64,role=oss-builder": [
      [
          "el",
          "5",
          "x86_64"
      ],
      [
          "sles",
          "11.2",
          "x86_64"
      ]
  ],
  "build_os=centos-5,machine_architecture=x86,role=oss-builder": [
      [
          "el",
          "5",
          "i686"
      ],
      [
          "sles",
          "11.2",
          "i686"
      ]
  ]
}
E
  end

  let(:platform_map) do
    JSON.parse(platform_map_json)
  end

  # mapping of short platform names to longer ones.
  # This file lives in this script's directory under $project-platform-names.json
  let(:platform_name_map_json) do
    <<-E
{
  "el" : "Enterprise Linux",
  "debian" : "Debian",
  "mac_os_x" : "OS X",
  "ubuntu" : "Ubuntu",
  "solaris2" : "Solaris",
  "sles" : "SUSE Enterprise",
  "suse" : "openSUSE",
  "windows" : "Windows"
}
E
  end

  let(:platform_name_map) do
    JSON.parse(platform_name_map_json)
  end

  let(:directory_contents) do
    %w[
      build_os=centos-5,machine_architecture=x64,role=oss-builder/pkg/demoproject-10.22.0-1.el5.x86_64.rpm
      build_os=centos-5,machine_architecture=x64,role=oss-builder/pkg/BUILD_VERSION
      build_os=centos-5,machine_architecture=x86,role=oss-builder/pkg/demoproject-10.22.0-1.el5.i686.rpm
      build_os=centos-5,machine_architecture=x86,role=oss-builder/pkg/BUILD_VERSION
    ]
  end

  let(:build_configurations) do
    %w[
      build_os=centos-5,machine_architecture=x64,role=oss-builder/jenkins
      build_os=centos-5,machine_architecture=x64,role=oss-builder/jenkins
      build_os=centos-5,machine_architecture=x86,role=oss-builder/jenkins
      build_os=centos-5,machine_architecture=x86,role=oss-builder/jenkins
    ]
  end

  let(:release_config_dir) { "build_os=centos-5,machine_architecture=x64,role=oss-builder/jenkins" }

  subject(:artifact_collection) do
    Omnibus::ArtifactCollection.new("demoproject", {})
  end

  it "has a project name" do
    artifact_collection.project.should == "demoproject"
  end

  it "has config" do
    artifact_collection.config.should == {}
  end

  it "selects a build to load release configurations from" do
    Dir.should_receive(:[]).with("*/jenkins").and_return(build_configurations)
    artifact_collection.release_config_dir.should == release_config_dir
  end


  it "loads the mapping of build platforms to install platforms from the local copy" do
    expected_path = "#{release_config_dir}/demoproject.json"
    Dir.should_receive(:[]).with("*/jenkins").and_return(build_configurations)
    IO.should_receive(:read).with(expected_path).and_return(platform_map_json)
    artifact_collection.platform_map_json.should == platform_map_json
  end

  it "loads the mapping of platform short names to long names from the local copy" do
    Dir.should_receive(:[]).with("*/jenkins").and_return(build_configurations)
    expected_path = "#{release_config_dir}/demoproject-platform-names.json"
    IO.should_receive(:read).with(expected_path).and_return(platform_name_map_json)
    artifact_collection.platform_name_map_json.should == platform_name_map_json
  end

  it "finds the package files among the artifacts" do
    Dir.should_receive(:[]).with("**/pkg/*").and_return(directory_contents)
    expected = %w[
      build_os=centos-5,machine_architecture=x64,role=oss-builder/pkg/demoproject-10.22.0-1.el5.x86_64.rpm
      build_os=centos-5,machine_architecture=x86,role=oss-builder/pkg/demoproject-10.22.0-1.el5.i686.rpm
    ]
    artifact_collection.package_paths.should == expected
  end

  context "after loading the build and platform mappings" do

    before do
      artifact_collection.should respond_to(:platform_map_json)
      artifact_collection.stub!(:platform_map_json).and_return(platform_map_json)
      artifact_collection.should respond_to(:platform_name_map_json)
      artifact_collection.stub!(:platform_name_map_json).and_return(platform_name_map_json)
    end

    it "parses the build platform mapping" do
      artifact_collection.platform_map.should == platform_map
    end

    it "parses the platform short name => long name mapping" do
      artifact_collection.platform_name_map.should == platform_name_map
    end

    it "returns a list of artifacts for each package" do
      Dir.should_receive(:[]).with("**/pkg/*").and_return(directory_contents)

      artifact_collection.should have(2).artifacts
      centos5_64bit_artifact = artifact_collection.artifacts.first

      path = "build_os=centos-5,machine_architecture=x64,role=oss-builder/pkg/demoproject-10.22.0-1.el5.x86_64.rpm"
      centos5_64bit_artifact.path.should == path

      platforms = [ [ "el", "5", "x86_64" ], [ "sles","11.2","x86_64" ] ]
      centos5_64bit_artifact.platforms.should == platforms
    end

    context "and some expected packages are missing" do
      let(:directory_contents) do
        %w[
          build_os=centos-5,machine_architecture=x86,role=oss-builder/pkg/demoproject-10.22.0-1.el5.i686.rpm
          build_os=centos-5,machine_architecture=x86,role=oss-builder/pkg/BUILD_VERSION
        ]
      end

      before do
        Dir.should_receive(:[]).with("**/pkg/*").and_return(directory_contents)
      end

      it "errors out verifying all packages are available" do
        err_msg = "Missing packages for config(s): 'build_os=centos-5,machine_architecture=x64,role=oss-builder'"
        lambda {artifact_collection.artifacts}.should raise_error(Omnibus::MissingArtifact, err_msg)
      end

    end
  end

end

