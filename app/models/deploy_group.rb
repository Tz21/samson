class DeployGroup < ActiveRecord::Base
  has_soft_deletion default_scope: true

  belongs_to :environment
  has_and_belongs_to_many :stages

  validates_presence_of :name, :environment_id
  validates_uniqueness_of :name

  def deploys
    Deploy.where(stage: stage_ids)
  end

  def long_name
    "#{name} (#{environment.name})"
  end
end
