require 'test_helper'

class HostgroupTest < ActiveSupport::TestCase
  setup do
    User.current = users :admin
  end

  should validate_presence_of(:name)
  should validate_uniqueness_of(:name)
  should allow_value(nil).for(:root_pass)
  should validate_length_of(:root_pass).is_at_least(8).
    with_message('should be 8 characters or more')

  test "name strips leading and trailing white spaces" do
    host_group = Hostgroup.new :name => " all    hosts in the     world    "
    assert host_group.save
    refute host_group.name.ends_with?(' ')
    refute host_group.name.starts_with?(' ')
  end

  test "should be able to nest a group parameters" do
    # creates a 3 level hirecy, each one with his own parameters
    # and overrides.
    pid = Time.now.to_i
    top = Hostgroup.new(:name => "topA",
                        :group_parameters_attributes => { pid += 1 => {"name" => "topA", "value" => "1"},
                                                          pid += 1 => {"name" => "topB", "value" => "1"},
                                                          pid += 1 => {"name" => "topC", "value" => "1"}})
    assert top.save

    second = Hostgroup.new(:name => "SecondA", :parent_id => top.id,
                           :group_parameters_attributes => { pid += 1 => {"name" => "topA", "value" => "2"},
                                                             pid += 1 => {"name" => "secondA", "value" => "2"}})
    assert second.save

    assert second.parameters.include? "topA"
    assert_equal "2", second.parameters["topA"]
    assert second.parameters.include? "topB"
    assert_equal "1", second.parameters["topB"]
    assert second.parameters.include? "topC"
    assert_equal "1", second.parameters["topC"]
    assert second.parameters.include? "secondA"
    assert_equal "2", second.parameters["secondA"]

    third = Hostgroup.new(:name => "ThirdA", :parent_id => second.id,
                          :group_parameters_attributes => { pid += 1 => {"name"=>"topB", "value"=>"3"},
                                                            pid +  1 => {"name"=>"topA", "value"=>"3"}})
    assert third.save

    assert third.parameters.include? "topA"
    assert_equal "3", third.parameters["topA"]
    assert third.parameters.include? "topB"
    assert_equal "3", third.parameters["topB"]
    assert third.parameters.include? "topC"
    assert_equal "1", third.parameters["topC"]
    assert third.parameters.include? "secondA"
    assert_equal "2", third.parameters["secondA"]
  end

  test "should inherit parent classes" do
    child = nil
    as_admin do
      top = Hostgroup.create!(:name => "topA")
      top.puppetclasses << Puppetclass.first
      child = Hostgroup.create!(:name => "secondB", :parent_id => top.id)
      child.puppetclasses << Puppetclass.last
    end

    assert_equal [Puppetclass.first, Puppetclass.last].sort, child.classes.sort
  end

  test "should show parent parameters" do
    pid = Time.now.to_i
    child = nil

    as_admin do
      top = FactoryGirl.create(:hostgroup, :name => "topA",
                               :group_parameters_attributes => { pid += 1 => {"name" => "topA", "value" => "1"},
                                                                 pid += 1 => {"name" => "topB", "value" => "1"}})
      child = Hostgroup.create!(:name => "secondB", :parent_id => top.id)
    end

    assert_equal({ "topA" => "1", "topB" => "1" }, child.parent_params)
  end

  test "blocks deletion of hosts with children" do
    top = Hostgroup.create(:name => "topA")
    Hostgroup.create(:name => "secondB", :parent_id => top.id)

    assert top.has_children?
    assert_raise Ancestry::AncestryException do
      top.destroy
    end
  end

  test "changing name of hostgroup updates other hostgroup labels" do
    #setup - add parent to hostgroup :common (not in fixtures, since no field parent_id)
    hostgroup = hostgroups(:db)
    parent_hostgroup = hostgroups(:common)
    hostgroup.parent_id = parent_hostgroup.id
    assert hostgroup.save!

    # change name of parent
    assert parent_hostgroup.update_attributes(:name => "new_common")
    # check if hostgroup(:db) label changed
    hostgroup.reload
    assert_equal "new_common/db", hostgroup.title
  end

  test "deleting a hostgroup with children does not change labels" do
    #setup - get label "common/db"
    hostgroup = hostgroups(:db)
    parent_hostgroup = hostgroups(:common)
    hostgroup.parent_id = parent_hostgroup.id
    assert hostgroup.save!
    hostgroup.reload
    assert_equal "Common/db", hostgroup.title

    #attempt to destroy parent hostgroup
    begin
      assert_not parent_hostgroup.destroy
      rescue Ancestry::AncestryException
    end
    # check if hostgroup(:db) label remains the same
    hostgroup.reload
    assert_equal "Common/db", hostgroup.title
  end

  test "should find associated lookup_values" do
    assert_equal [lookup_values(:hostgroupcommon), lookup_values(:four)].map(&:id).sort, hostgroups(:common).lookup_values.map(&:id).sort
  end

  test "should find associated lookup_values with unsafe SQL name" do
    hostgroup = hostgroups(:common)
    hostgroup.name = "Robert';"
    hostgroup.save!
    lv = lookup_values(:four)
    lv.match = "hostgroup=#{hostgroup.name}"
    lv.save!
    assert_equal [lookup_values(:hostgroupcommon), lookup_values(:four)].map(&:id).sort, hostgroup.lookup_values.map(&:id).sort
  end

  # test NestedAncestryCommon methods generate by class method nested_attribute_for
  test "respond to nested_attribute_for methods" do
    hostgroup = hostgroups(:common)
    [:compute_profile_id, :environment_id, :domain_id, :puppet_proxy_id, :puppet_ca_proxy_id,
     :operatingsystem_id, :architecture_id, :medium_id, :ptable_id, :subnet_id].each do |field|
      assert hostgroup.respond_to?("inherited_#{field}")
    end
  end

  test "inherited id value equals field id value if no ancestry" do
    hostgroup = hostgroups(:common)
    [:compute_profile_id, :environment_id, :domain_id, :puppet_proxy_id, :puppet_ca_proxy_id,
     :operatingsystem_id, :architecture_id, :medium_id, :ptable_id, :subnet_id].each do |field|
      assert_equal hostgroup.send(field), hostgroup.send("inherited_#{field}")
    end
  end

  test "inherited id value equals parent's field id value if the child's value is null" do
    child = hostgroups(:inherited)
    parent = hostgroups(:parent)
    # environment_id is not included in the array below since child value is not null
    [:compute_profile_id, :domain_id, :puppet_proxy_id, :puppet_ca_proxy_id,
     :operatingsystem_id, :architecture_id, :medium_id, :ptable_id, :subnet_id].each do |field|
      assert_equal parent.send(field), child.send("inherited_#{field}")
    end
  end

  test "inherited id value does not inherit parent's field id value if the child's value is not null" do
    child = hostgroups(:inherited)
    parent = hostgroups(:parent)
    # only environment_id is overriden in inherited fixture
    refute_equal parent.environment_id, child.inherited_environment_id
    assert_equal child.environment_id, child.inherited_environment_id
  end

  test "inherited object equals parent object if the child's value is null" do
    child = hostgroups(:inherited)
    parent = hostgroups(:parent)
    # methods below do not include _id
    # environment is not included in the array below since child value is not null
    [:compute_profile, :domain, :puppet_proxy, :puppet_ca_proxy,
     :operatingsystem, :architecture, :medium, :ptable, :subnet].each do |field|
      assert_equal parent.send(field), child.send(field)
    end
  end

  test "inherited object does not inherit parent object if the child's value is null" do
    child = hostgroups(:inherited)
    parent = hostgroups(:parent)
    # only environment_id is overriden in inherited fixture
    refute_equal parent.environment, child.environment
    assert_equal environments(:production), child.environment
  end

  test "classes_in_groups should return the puppetclasses of a config group only if it is in hostgroup environment" do
    # config_groups(:one) and (:three) belongs to hostgroups(:common)
    hostgroup = hostgroups(:common)
    group_classes = hostgroup.classes_in_groups
    # four classes in config groups
    assert_equal 4, (config_groups(:one).puppetclasses + config_groups(:three).puppetclasses).uniq.count
    # but only 3 are in production environment. git is in testing environment
    assert_equal 3, group_classes.count
    assert_equal ['chkmk', 'nagios', 'vim'].sort, group_classes.map(&:name).sort
  end

  test "should return all classes for environment only" do
    # config_groups(:one) and (:three) belongs to hostgroup(:common)
    hostgroup = hostgroups(:common)
    all_classes = hostgroup.classes
    # three classes from group plus one class directly - base
    assert_equal 4, all_classes.count
    assert_equal ['base', 'chkmk', 'nagios', 'vim'].sort, all_classes.map(&:name).sort
  end

  test "search hostgroups by config group" do
    config_group = config_groups(:one)
    hostgroups = Hostgroup.search_for("config_group = #{config_group.name}")
    assert_equal 3, hostgroups.count
    assert_equal ["Common", "Parent", "inherited"].sort, hostgroups.map(&:name).sort
  end

  test "parent_classes should return parent classes if hostgroup has parent and environment are the same" do
    hostgroup = hostgroups(:inherited)
    assert hostgroup.parent
    # update environment for this test to be same as parent
    hostgroup.parent.update_attribute(:environment_id, hostgroup.environment_id)
    refute_empty hostgroup.parent_classes
    assert_equal hostgroup.parent_classes, hostgroup.parent.classes
  end

  test "parent_classes should not return parent classes that do not match environment" do
    hostgroup = hostgroups(:inherited)
    assert hostgroup.parent
    refute_empty hostgroup.parent_classes
    refute_equal hostgroup.environment, hostgroup.parent.environment
    refute_equal hostgroup.parent_classes, hostgroup.parent.classes
  end

  test "parent_classes should return empty array if hostgroup does not has parent" do
    hostgroup = hostgroups(:common)
    assert_nil hostgroup.parent
    assert_empty hostgroup.parent_classes
  end

  test "parent_config_groups should return parent config_groups if hostgroup has parent - 2 levels" do
    hostgroup = hostgroups(:inherited)
    assert hostgroup.parent
    assert_equal hostgroup.parent_config_groups, hostgroup.parent.config_groups
  end

  test "parent_config_groups should return parent config_groups if hostgroup has parent  - 3 levels" do
    assert hostgroup = Hostgroup.create!(:name => 'third level', :parent_id => hostgroups(:inherited).id)
    groups = (hostgroup.config_groups + hostgroup.parent.config_groups + hostgroup.parent.parent.config_groups).uniq.sort
    assert_equal groups, hostgroup.parent_config_groups.sort
  end

  test "parent_config_groups should return empty array if hostgroup does not has parent" do
    hostgroup = hostgroups(:common)
    assert_nil hostgroup.parent
    assert_empty hostgroup.parent_config_groups
  end

  test "individual puppetclasses added to hostgroup (that can be removed) does not include classes that are included by config group" do
    hostgroup = hostgroups(:parent)
    # update parent to production environment
    hostgroup.update_attribute(:environment_id, environments(:production).id)
    # nagios puppetclasses(:five) is also in config_groups(:one) Monitoring
    hostgroup.puppetclasses << puppetclasses(:five)
    assert_equal ['git', 'nagios'].sort, hostgroup.puppetclasses.map(&:name).sort
    assert_equal [], hostgroup.individual_puppetclasses.map(&:name)
  end

  test "available_puppetclasses should return all if no environment" do
    hostgroup = hostgroups(:common)
    hostgroup.update_attribute(:environment_id, nil)
    assert_equal Puppetclass.all, hostgroup.available_puppetclasses
  end

  test "available_puppetclasses should return environment-specific classes" do
    hostgroup = hostgroups(:common)
    refute_equal Puppetclass.all, hostgroup.available_puppetclasses
    assert_equal hostgroup.environment.puppetclasses.sort, hostgroup.available_puppetclasses.sort
  end

  test "available_puppetclasses should return environment-specific classes (and that are NOT already inherited by parent)" do
    hostgroup = hostgroups(:inherited)
    refute_equal Puppetclass.all, hostgroup.available_puppetclasses
    refute_equal hostgroup.environment.puppetclasses.sort, hostgroup.available_puppetclasses.sort
    assert_equal (hostgroup.environment.puppetclasses - hostgroup.parent_classes).sort, hostgroup.available_puppetclasses.sort
  end

  test "root_pass inherited from parent if blank" do
    parent = FactoryGirl.create(:hostgroup, :root_pass => '12345678')
    hostgroup = FactoryGirl.build(:hostgroup, :parent => parent, :root_pass => '')
    assert_equal parent.read_attribute(:root_pass), hostgroup.root_pass
    hostgroup.save!
    assert hostgroup.read_attribute(:root_pass).blank?, 'root_pass should not be copied and stored on child'
  end

  test "root_pass inherited from settings if blank" do
    Setting[:root_pass] = '12345678'
    hostgroup = FactoryGirl.build(:hostgroup, :root_pass => '')
    assert_equal '12345678', hostgroup.root_pass
    hostgroup.save!
    assert hostgroup.read_attribute(:root_pass).blank?, 'root_pass should not be copied and stored on child'
  end

  test "root_pass inherited from settings if group and parent are blank" do
    Setting[:root_pass] = '12345678'
    parent = FactoryGirl.create(:hostgroup, :root_pass => '')
    hostgroup = FactoryGirl.build(:hostgroup, :parent => parent, :root_pass => '')
    assert_equal '12345678', hostgroup.root_pass
    hostgroup.save!
    assert hostgroup.read_attribute(:root_pass).blank?, 'root_pass should not be copied and stored on child'
  end

  test "hostgroup name can't be too big to create lookup value matcher over 255 characters" do
    parent = FactoryGirl.create(:hostgroup)
    min_lookupvalue_length = "hostgroup=".length + parent.title.length + 1
    hostgroup = Hostgroup.new :parent => parent, :name => 'a' * 256
    refute_valid hostgroup
    assert_equal "is too long (maximum is %s characters)" % (255 -  min_lookupvalue_length), hostgroup.errors[:name].first
  end

  test "hostgroup name can be up to 255 characters" do
    parent = FactoryGirl.create(:hostgroup)
    min_lookupvalue_length = "hostgroup=".length + parent.title.length + 1
    hostgroup = Hostgroup.new :parent => parent, :name => 'a' * (255 - min_lookupvalue_length)
    assert_valid hostgroup
  end

  test "hostgroup should not save when matcher is exactly 256 characters" do
    parent = FactoryGirl.create(:hostgroup, :name => 'a' * 244)
    hostgroup = Hostgroup.new :parent => parent, :name => 'b'
    refute_valid hostgroup
    assert_equal _("is too long (maximum is 0 characters)"),  hostgroup.errors[:name].first
  end

  test "to_param" do
    parent = FactoryGirl.create(:hostgroup, :name => 'a')
    hostgroup = Hostgroup.new(:parent => parent, :name => 'b')
    assert_equal "#{hostgroup.id}-a-b",  hostgroup.to_param
  end

  test "to_param calls ancestry when title is not yet saved" do
    parent = FactoryGirl.create(:hostgroup, :name => 'a')
    hostgroup = Hostgroup.new(:parent => parent, :name => 'b')
    hostgroup.expects(:ancestry).once
    hostgroup.to_param
  end

  test "to_param doesn't call ancestry when title is saved" do
    parent = FactoryGirl.create(:hostgroup, :name => 'a')
    hostgroup = Hostgroup.create(:parent => parent, :name => 'b')
    hostgroup.expects(:ancestry).never
    hostgroup.to_param
  end

  context "#clone" do
    let(:group) {FactoryGirl.create(:hostgroup, :name => 'a')}

    test "clone should clone config groups as well" do
      config_group = ConfigGroup.create!(:name => 'Blah')
      group.config_groups << config_group

      cloned = group.clone("new_name")
      assert cloned.config_groups.include?(config_group)
    end

    test "clone should clone puppet classes" do
      group.puppetclasses << FactoryGirl.create(:puppetclass)
      cloned = group.clone("new_name")
      assert_equal group.hostgroup_classes.map(&:puppetclass_id), cloned.hostgroup_classes.map(&:puppetclass_id)
    end

    test "clone should clone parameters values but update ids" do
      group.group_parameters.create!(:name => "foo", :value => "bar")
      cloned = group.clone("new_name")
      cloned.save
      assert_equal cloned.group_parameters.map{|p| [p.name, p.value]}, group.group_parameters.map{|p| [p.name, p.value]}
      refute_equal cloned.group_parameters.map{|p| p.id}, group.group_parameters.map{|p| p.id}
      refute_equal cloned.group_parameters.map{|p| p.reference_id}, group.group_parameters.map{|p| p.reference_id}
    end

    test "clone should clone lookup values" do
      lv = lookup_values(:four)
      lv.match = group.send(:lookup_value_match)
      lv.save!
      cloned = group.clone("new_name")
      cloned.save!
      assert_equal 1, group.lookup_values.reload.count
      assert_equal 1, cloned.lookup_values.count
      assert_equal group.lookup_values.map(&:value), cloned.lookup_values.map(&:value)
    end

    test '#classes etc. on cloned group return the same' do
      parent = FactoryGirl.create(:hostgroup, :with_config_group, :with_puppetclass)
      group = FactoryGirl.create(:hostgroup, :with_config_group, :with_puppetclass, :parent => parent)
      cloned = group.clone('cloned')
      assert_equal group.individual_puppetclasses.map(&:id), cloned.individual_puppetclasses.map(&:id)
      assert_equal group.classes_in_groups.map(&:id), cloned.classes_in_groups.map(&:id)
      assert_equal group.classes.map(&:id), cloned.classes.map(&:id)
      assert_equal group.available_puppetclasses.map(&:id), cloned.available_puppetclasses.map(&:id)
      assert_valid cloned
    end

    test 'without save makes no changes' do
      group = FactoryGirl.create(:hostgroup, :with_config_group, :with_puppetclass)
      FactoryGirl.create(:puppetclass_lookup_key, :as_smart_class_param, :with_override, :puppetclass => group.puppetclasses.first, :overrides => {group.lookup_value_matcher => 'test'})
      ActiveRecord::Base.any_instance.expects(:destroy).never
      ActiveRecord::Base.any_instance.expects(:save).never
      group.clone
    end

    test "clone with config group should run validations once" do
      group = FactoryGirl.create(:hostgroup, :with_config_group)
      cloned = group.clone
      refute cloned.valid?
      assert_equal 1, cloned.errors[:name].size
    end

    test "when updating environment for a new (or cloned) hostgroup, the individual_puppetclasses method should return correctly" do
      group = FactoryGirl.create(:hostgroup, :with_config_group, :with_puppetclass)
      cloned = Hostgroup.new
      cloned.puppetclasses = group.puppetclasses
      assert_equal cloned.individual_puppetclasses, group.individual_puppetclasses
    end
  end

  describe '#param_true?' do
    test 'returns false for unknown parameter' do
      Foreman::Cast.expects(:to_bool).never
      refute FactoryGirl.build(:hostgroup).param_true?('unknown')
    end

    test 'returns false for parameter with false-like value' do
      Foreman::Cast.expects(:to_bool).with('0').returns(false)
      group = FactoryGirl.create(:hostgroup)
      FactoryGirl.create(:hostgroup_parameter, :hostgroup => group, :name => 'group_param', :value => '0')
      refute group.reload.param_true?('group_param')
    end

    test 'returns true for parameter with true-like value' do
      Foreman::Cast.expects(:to_bool).with('1').returns(true)
      group = FactoryGirl.create(:hostgroup)
      FactoryGirl.create(:hostgroup_parameter, :hostgroup => group, :name => 'group_param', :value => '1')
      assert group.reload.param_true?('group_param')
    end

    test 'uses inherited parameters' do
      Foreman::Cast.expects(:to_bool).with('1').returns(true)
      group = FactoryGirl.create(:hostgroup, :with_parent)
      FactoryGirl.create(:hostgroup_parameter, :hostgroup => group.parent, :name => 'group_param', :value => '1')
      assert group.reload.param_true?('group_param')
    end
  end

  describe '#param_false?' do
    test 'returns false for unknown parameter' do
      Foreman::Cast.expects(:to_bool).never
      refute FactoryGirl.build(:hostgroup).param_false?('unknown')
    end

    test 'returns true for parameter with false-like value' do
      Foreman::Cast.expects(:to_bool).with('0').returns(false)
      group = FactoryGirl.create(:hostgroup)
      FactoryGirl.create(:hostgroup_parameter, :hostgroup => group, :name => 'group_param', :value => '0')
      assert group.reload.param_false?('group_param')
    end

    test 'returns false for parameter with true-like value' do
      Foreman::Cast.expects(:to_bool).with('1').returns(true)
      group = FactoryGirl.create(:hostgroup)
      FactoryGirl.create(:hostgroup_parameter, :hostgroup => group, :name => 'group_param', :value => '1')
      refute group.reload.param_false?('group_param')
    end

    test 'uses inherited parameters' do
      Foreman::Cast.expects(:to_bool).with('0').returns(false)
      group = FactoryGirl.create(:hostgroup, :with_parent)
      FactoryGirl.create(:hostgroup_parameter, :hostgroup => group.parent, :name => 'group_param', :value => '0')
      assert group.reload.param_false?('group_param')
    end
  end

  test 'should update hosts_count' do
    host = FactoryGirl.create(:host)
    hostgroup = FactoryGirl.create(:hostgroup)
    assert_difference "hostgroup.hosts_count" do
      host.update_attributes(:hostgroup => hostgroup)
      hostgroup.reload
    end
  end

  test '#children_hosts_count' do
    group = FactoryGirl.create(:hostgroup, :with_parent)
    FactoryGirl.create_list(:host, 3, :managed, :hostgroup => group )
    assert_equal(3, group.parent.children_hosts_count)
    nested_group = FactoryGirl.create(:hostgroup, :parent => group)
    FactoryGirl.create_list(:host, 4, :managed, :hostgroup => nested_group )
    assert_equal(7, group.parent.children_hosts_count)
  end

  test "should not associate proxies without appropriate features" do
    proxy = smart_proxies(:one)
    hostgroup = Hostgroup.new(:name => ".otherDomain.", :puppet_proxy_id => proxy.id, :puppet_ca_proxy_id => proxy.id)
    refute hostgroup.save
    assert_equal "does not have the Puppet feature", hostgroup.errors["puppet_proxy_id"].first
    assert_equal "does not have the Puppet CA feature", hostgroup.errors["puppet_ca_proxy_id"].first
  end

  private

  def setup_user(operation)
    super operation, "hostgroups"
  end
end
