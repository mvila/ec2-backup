#!/usr/bin/env coffee

path = require 'path'
fs = require 'fs'
_ = require 'underscore'
request = require 'request'
aws = require 'aws-lib'
moment = require 'moment'
async = require 'async'

log = (type, msg) ->
  date = moment().format 'YYYY-MM-DDTHH:mm:ss'
  console[type] "#{date} [#{type}] #{msg}"
info = (msg) -> log 'info', msg
error = (msg) -> log 'error', msg

process.on 'uncaughtException', (err) ->
  error err.message
  process.exit 1

getMetadata = (done) ->
  request.get 'http://169.254.169.254/latest/dynamic/instance-identity/document', (err, res, body) ->
    throw new Error "unable to get metadata" unless res.statusCode is 200
    done JSON.parse body

loadConfig = ->
  configPath = path.join __dirname, 'config.json'
  unless fs.existsSync configPath
    home = if process.platform isnt 'win32' then 'HOME' else 'USERPROFILE'
    configPath = path.join process.env[home], '.aws', 'config.json'
    unless fs.existsSync configPath
      throw new Error "config file not found"
  config = fs.readFileSync configPath, 'utf8'
  JSON.parse config

createEC2Client = (region) ->
  config = loadConfig()
  throw new Error "'config.accessKeyId' is undefined" unless config.accessKeyId
  throw new Error "'config.secretAccessKey' is undefined" unless config.secretAccessKey
  host = "ec2.#{region}.amazonaws.com"
  version = '2012-10-01'
  aws.createEC2Client config.accessKeyId, config.secretAccessKey, { host, version }

itemToArray = (item) ->
  return item if _.isArray item
  return [] unless item
  [item]

itemToObject = (item) ->
  item = itemToArray item
  obj = {}
  obj[prop.key] = prop.value for prop in item
  obj

getMetadata (metadata) ->
  ec2 = createEC2Client metadata.region

  getInstance = (done) ->
    ec2.call 'DescribeInstances', { InstanceId: metadata.instanceId }, (err, result) ->
      throw new Error 'unable to get instance' if err
      done result.reservationSet.item.instancesSet.item

  getVolume = (volumeId, done) ->
    ec2.call 'DescribeVolumes', { VolumeId: volumeId }, (err, result) ->
      throw new Error "unable to get volume '#{volumeId}'" if err
      done result.volumeSet.item

  createSnapshot = (volume, done) ->
    ec2.call 'CreateSnapshot', { VolumeId: volume.volumeId, Description: 'automated backup' }, (err, result) ->
      throw new Error 'unable to create snapshot' if err
      snapshotId = result.snapshotId
      throw new Error "volume '#{volume.volumeId}' hasn't any tag" unless volume.tagSet
      name = itemToObject(volume.tagSet.item).Name
      throw new Error "volume '#{volume.volumeId}' hasn't any name" unless name
      name += '-' + moment().format 'YYYY-MM-DD'
      options =
        'ResourceId.1': snapshotId
        'ResourceId.2': snapshotId
        'Tag.1.Key': 'Name'
        'Tag.1.Value': name
        'Tag.2.Key': 'X-Is-Purgeable'
        'Tag.2.Value': 'true'
      ec2.call 'CreateTags', options, (err, result) ->
        throw new Error "unable to create snapshot tags" if err
        info "snapshot '#{snapshotId}' created"
        done snapshotId

  getPurgeableSnapshots = (volume, done) ->
    options =
      'Owner': 'self'
      'Filter.1.Name': 'status'
      'Filter.1.Value': 'completed'
      'Filter.2.Name': 'volume-id'
      'Filter.2.Value': volume.volumeId
      'Filter.3.Name': 'tag:X-Is-Purgeable'
      'Filter.3.Value': 'true'
    ec2.call 'DescribeSnapshots', options, (err, result) ->
      throw new Error 'unable to get existing snapshots' if err
      snapshots = itemToArray result.snapshotSet.item
      purgeableSnapshots = []
      tenDaysAgo = moment().subtract 10, 'days'
      tenWeeksAgo = moment().subtract 10, 'weeks'
      tenMonthsAgo = moment().subtract 10, 'months'
      for snapshot in snapshots
        date = moment snapshot.startTime
        continue if date.diff(tenDaysAgo) > 0 # 10 last days
        continue if date.diff(tenWeeksAgo) > 0 and date.day() is 1 # 10 last mondays
        continue if date.diff(tenMonthsAgo) > 0 and date.date() is 1 # First day of 10 last months
        purgeableSnapshots.push snapshot
      done purgeableSnapshots

  purgeSnapshots = (snapshots, done) ->
    purge = (snapshot, next) ->
      id = snapshot.snapshotId
      ec2.call 'DeleteSnapshot', { SnapshotId: id }, (err, result) ->
        throw new Error "unable to delete snapshot '#{id}'" if err
        info "snapshot '#{id}' deleted"
        next()
    async.forEachSeries snapshots, purge, done

  getInstance (instance) ->
    devices = itemToArray instance.blockDeviceMapping.item
    async.forEachSeries devices, (device, next) ->
      volumeId = device.ebs.volumeId
      getVolume volumeId, (volume) ->
        createSnapshot volume, ->
          getPurgeableSnapshots volume, (snapshots) ->
            purgeSnapshots snapshots, ->
              next()
