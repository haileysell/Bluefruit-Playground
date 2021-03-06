//
//  BlePeripehral+CPBCommon.swift
//  BluefruitPlayground
//
//  Created by Antonio García on 13/11/2019.
//  Copyright © 2019 Adafruit. All rights reserved.
//

import Foundation
import CoreBluetooth

extension BlePeripheral {
    // Costants
    private static let kCPBMeasurementPeriodCharacteristicUUID =  CBUUID(string: "ADAF0001-C332-42A8-93BD-25E905756CB8")
    private static let kCPBMeasurementVersionCharacteristicUUID =  CBUUID(string: "ADAF0002-C332-42A8-93BD-25E905756CB8")
    
    private static let kCPBDefaultVersionValue = 1         // Used as default version value if version characteristic cannot be read
    
    // MARK: - Errors
    enum PeripheralCPBError: Error {
        case invalidCharacteristic
        case enableNotifyFailed
        case unknownVersion
        case invalidResponseData
    }
    
    // MARK: - Custom properties
    /*
    private struct CustomPropertiesKeys {
        static var cpbMeasurementPeriodCharacteristic: CBCharacteristic?
        //static var cpbVersionCharacteristic: CBCharacteristic?
    }
    
    private var cpbMeasurementPeriodCharacteristic: CBCharacteristic? {
        get {
            return objc_getAssociatedObject(self, &CustomPropertiesKeys.cpbMeasurementPeriodCharacteristic) as! CBCharacteristic?
        }
        set {
            objc_setAssociatedObject(self, &CustomPropertiesKeys.cpbMeasurementPeriodCharacteristic, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    private var cpbVersionCharacteristic: CBCharacteristic? {
        get {
            return objc_getAssociatedObject(self, &CustomPropertiesKeys.cpbVersionCharacteristic) as! CBCharacteristic?
        }
        set {
            objc_setAssociatedObject(self, &CustomPropertiesKeys.cpbVersionCharacteristic, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }*/
    
    // MARK: - Service Actions
    func cpbServiceEnable(serviceUuid: CBUUID, mainCharacteristicUuid: CBUUID, completion: ((Result<(Int, CBCharacteristic), Error>) -> Void)?) {
        
        self.characteristic(uuid: mainCharacteristicUuid, serviceUuid: serviceUuid) { [unowned self] (characteristic, error) in
            guard let characteristic = characteristic, error == nil else {
                completion?(.failure(error ?? PeripheralCPBError.invalidCharacteristic))
                return
            }
            
            // Check version
            self.cpbVersion(serviceUuid: serviceUuid) { version in
                completion?(.success((version, characteristic)))
            }
        }
    }
    
    func cpbServiceEnable(serviceUuid: CBUUID, mainCharacteristicUuid: CBUUID, timePeriod: TimeInterval?, responseHandler: @escaping(Result<(Data, UUID), Error>) -> Void, completion: ((Result<(Int, CBCharacteristic), Error>) -> Void)?) {
        
        self.characteristic(uuid: mainCharacteristicUuid, serviceUuid: serviceUuid) { [unowned self] (characteristic, error) in
            guard let characteristic = characteristic, error == nil else {
                completion?(.failure(error ?? PeripheralCPBError.invalidCharacteristic))
                return
            }
            
            // Check version
            self.cpbVersion(serviceUuid: serviceUuid) { version in
                // Prepare notification handler
                let notifyHandler: ((Error?) -> Void)? = { [unowned self] error in
                    guard error == nil else {
                        responseHandler(.failure(error!))
                        return
                    }
                    
                    if let data = characteristic.value {
                        responseHandler(.success((data, self.identifier)))
                    }
                }
                
                // Refresh period handler
                let enableNotificationsHandler = {
                    // Enable notifications
                    if !characteristic.isNotifying {
                        self.enableNotify(for: characteristic, handler: notifyHandler, completion: { error in
                            guard error == nil else {
                                completion?(.failure(error!))
                                return
                            }
                            guard characteristic.isNotifying else {
                                completion?(.failure(PeripheralCPBError.enableNotifyFailed))
                                return
                            }
                            
                            completion?(.success((version, characteristic)))
                            
                        })
                    } else {
                        self.updateNotifyHandler(for: characteristic, handler: notifyHandler)
                        completion?(.success((version, characteristic)))
                    }
                }
                
                // Set timePeriod if not nil
                if let timePeriod = timePeriod {
                    self.cpbSetPeriod(timePeriod, serviceUuid: serviceUuid) { result in
                        
                        if Config.isDebugEnabled {
                            // Check period
                            self.cpbPeriod(serviceUuid: serviceUuid) { period in
                                DLog("service period: \(String(describing: period))")
                            }
                        }
                        
                        enableNotificationsHandler()
                    }
                }
                else {
                    enableNotificationsHandler()
                }
            }
        }
    }
    
    func cpbVersion(serviceUuid: CBUUID, completion: @escaping(Int) -> Void) {
        self.characteristic(uuid: BlePeripheral.kCPBMeasurementVersionCharacteristicUUID, serviceUuid: serviceUuid) { (characteristic, error) in
            
            guard error == nil, let characteristic = characteristic, let data = characteristic.value else {
                completion(BlePeripheral.kCPBDefaultVersionValue)
                return
            }
            let version = data.toIntFrom32Bits()
            completion(version)
        }
    }
    
    
    func cpbPeriod(serviceUuid: CBUUID, completion: @escaping(TimeInterval?) -> Void) {
        self.characteristic(uuid: BlePeripheral.kCPBMeasurementPeriodCharacteristicUUID, serviceUuid: serviceUuid) { (characteristic, error) in
            
            guard error == nil, let characteristic = characteristic else {
                completion(nil)
                return
            }

            self.readCharacteristic(characteristic) { (data, error) in
                guard error == nil, let data = data as? Data else {
                    completion(nil)
                    return
                }

                let period = TimeInterval(data.toIntFrom32Bits()) / 1000.0
                completion(period)
            }
        }
    }
    
    
    func cpbSetPeriod(_ period: TimeInterval, serviceUuid: CBUUID, completion: ((Result<Void, Error>) -> Void)?) {
        
        self.characteristic(uuid: BlePeripheral.kCPBMeasurementPeriodCharacteristicUUID, serviceUuid: serviceUuid) { (characteristic, error) in
            
            guard error == nil, let characteristic = characteristic else {
                DLog("Error: cpbSetPeriod: \(String(describing: error))")
                return
            }

            let periodMillis = Int32(period * 1000)
            let data = periodMillis.littleEndian.data
            self.write(data: data, for: characteristic, type: .withResponse) { error in
                guard error == nil else {
                    DLog("Error: cpbSetPeriod \(error!)")
                    completion?(.failure(error!))
                    return
                }
                
                completion?(.success(()))
            }
        }
    }
}
