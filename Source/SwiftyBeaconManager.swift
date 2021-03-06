//
//  BeaconManager.swift
//  iBeaconDemo
//
//  Created by Fedya Skitsko on 11/21/14.
//  Copyright (c) 2014 LabWerk. All rights reserved.
//

import Foundation
import UIKit
import CoreLocation
import CoreBluetooth

public enum SwiftyBeaconError: ErrorType {
    case MonitoringUnavailable
    case LocationServiceUnathorized
    case LocationServiceDisabled
    case BluetoothPoweredOff
}

public let SwiftyBeaconManagerDomain = "com.swiftybeaconmanager"

public typealias BeaconManagerAutorizationStateHandler = (CLAuthorizationStatus) -> Void
public typealias BeaconManagerBluetoothStateHandler = (CBCentralManagerState) -> Void

public class SwiftyBeaconManager: NSObject {
    // MARK: - Properties
    
    lazy var locationManager: CLLocationManager = {
        let locationManager = CLLocationManager()
        locationManager.delegate = self
        return locationManager
    }()
    
    lazy var bluetoothManager: CBCentralManager = {
        return CBCentralManager(delegate: self, queue: dispatch_get_main_queue(), options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }()
    
    private var hasAskedToSwitchOnBluetooth = false
    
    public var authorizationStateHandler: BeaconManagerAutorizationStateHandler?
    public var bluetoothStateHandler: BeaconManagerBluetoothStateHandler?
    
    private(set) var regions = Set<SwiftyBeaconRegion>()
    
    // MARK: - Init
    
    override public init() {
        super.init()
        
        if NSBundle.mainBundle().objectForInfoDictionaryKey("NSLocationWhenInUseUsageDescription") == nil { //check NSLocationWhenInUseUsageDescription
            if NSBundle.mainBundle().objectForInfoDictionaryKey("NSLocationAlwaysUsageDescription") == nil { //if NSLocationAlwaysUsageDescription also nil, then drop fatalError
                fatalError("Please add NSLocationAlwaysUsageDescription OR NSLocationWhenInUseUsageDescription to your Info.plist file")
            }
        }
    }

    // MARK: - Public methods
    
    public func startMonitoringRegion(region: SwiftyBeaconRegion) throws {
        if !CLLocationManager.locationServicesEnabled() || CLLocationManager.authorizationStatus() == .NotDetermined {
            locationManager.requestAlwaysAuthorization()
            return
        }
        
        if !CLLocationManager.isMonitoringAvailableForClass(CLBeaconRegion.self) {
            throw SwiftyBeaconError.MonitoringUnavailable
        }
        
        if CLLocationManager.locationServicesEnabled() {
            if CLLocationManager.authorizationStatus() != .AuthorizedAlways {
                throw SwiftyBeaconError.LocationServiceUnathorized
            }
        } else {
            throw SwiftyBeaconError.LocationServiceDisabled
        }
        
        if bluetoothManager.state != .PoweredOn {
            if hasAskedToSwitchOnBluetooth {
                throw SwiftyBeaconError.BluetoothPoweredOff
            } else {
                bluetoothManager.scanForPeripheralsWithServices(nil, options: nil)
                
                let delayTime = dispatch_time(DISPATCH_TIME_NOW, Int64(1 * Double(NSEC_PER_SEC)))
                dispatch_after(delayTime, dispatch_get_main_queue()) {
                    self.hasAskedToSwitchOnBluetooth = true
                }
            }
            return
        }
        
        if let index = regions.indexOf(region) {
            let oldRegion = regions[index]
            oldRegion.stateHandler = region.stateHandler
            oldRegion.rangeHandler = region.rangeHandler
            locationManager.requestStateForRegion(region)
        } else {
            regions.insert(region)
            locationManager.startMonitoringForRegion(region)
        }
    }
    
    public func stopMonitoringRegion(region: SwiftyBeaconRegion) {
        if regions.contains(region) {
            locationManager.stopMonitoringForRegion(region)
            regions.remove(region)
        }
    }
    
    public func stopMonitoringRegions() {
        for region in regions {
            locationManager.stopMonitoringForRegion(region)
            regions.remove(region)
        }
    }
   
    // MARK: - Private methods
    
    private func findBeaconRegion(region: CLRegion) -> SwiftyBeaconRegion? {
        for beaconRegion in regions {
            if beaconRegion.identifier == region.identifier {
                return beaconRegion
            }
        }
        
        return nil
    }
}

// MARK: - CBCentralManagerDelegate

extension SwiftyBeaconManager: CBCentralManagerDelegate {
    
    public func centralManagerDidUpdateState(central: CBCentralManager) {
        switch bluetoothManager.state {
        case .PoweredOn:
            for region in regions {
                locationManager.requestStateForRegion(region)
            }
        default:
            for region in regions {
                locationManager.stopRangingBeaconsInRegion(region)
            }
        }
        
        bluetoothStateHandler?(bluetoothManager.state)
    }
}

// MARK: - CLLocationManagerDelegate

extension SwiftyBeaconManager: CLLocationManagerDelegate {
    
    public func locationManager(manager: CLLocationManager, didChangeAuthorizationStatus status: CLAuthorizationStatus) {
        if status == .AuthorizedAlways {
            for region in regions {
                locationManager.requestStateForRegion(region)
            }
        }
        
        authorizationStateHandler?(status)
    }
    
    public func locationManager(manager: CLLocationManager, didStartMonitoringForRegion region: CLRegion) {
        if let beaconRegion = findBeaconRegion(region) {
            print("didStartMonitoringForRegion \(beaconRegion)")
        
            locationManager.requestStateForRegion(beaconRegion)
        }
    }
    
    public func locationManager(manager: CLLocationManager, didEnterRegion region: CLRegion) {
        if let beaconRegion = findBeaconRegion(region) {
            print("didEnterRegion \(beaconRegion)")
        }
    }
    
    public func locationManager(manager: CLLocationManager, didExitRegion region: CLRegion) {
        if let beaconRegion = findBeaconRegion(region) {
            print("didExitRegion \(beaconRegion)")
        }
    }
    
    public func locationManager(manager: CLLocationManager, didDetermineState state: CLRegionState, forRegion region: CLRegion) {
        if let beaconRegion = findBeaconRegion(region) {
            switch state {
                case .Inside:
                    print("Inside \(region)")
                    locationManager.startRangingBeaconsInRegion(beaconRegion)
                    beaconRegion.stateHandler?(.Inside)
                case .Outside:
                    print("Outside \(region)")
                    locationManager.stopRangingBeaconsInRegion(beaconRegion)
                    beaconRegion.stateHandler?(.Outside)
                case .Unknown:
                    print("Unknown \(region)")
                    beaconRegion.stateHandler?(.Unknown)
            }
        }
    }
    
    public func locationManager(manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], inRegion region: CLBeaconRegion) {
        if let beaconRegion = findBeaconRegion(region) {
            print("[INFO] didRangeBeacons region: \(region)")
            beaconRegion.rangeHandler?(beacons)
        
            print("Beacons: \(beacons)")
        }
    }
    
    public func locationManager(manager: CLLocationManager, monitoringDidFailForRegion region: CLRegion?, withError error: NSError) {
        if let region = region as? CLBeaconRegion, beaconRegion = findBeaconRegion(region) {
            print("[ERROR] monitoringDidFailForRegion \(beaconRegion): \(error)")
        }
    }
    
    public func locationManager(manager: CLLocationManager, rangingBeaconsDidFailForRegion region: CLBeaconRegion, withError error: NSError) {
        if let beaconRegion = findBeaconRegion(region) {
            print("[ERROR] rangingBeaconsDidFailForRegion \(beaconRegion): \(error)")
        }
    }
}
