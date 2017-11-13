//
//  File.swift
//  ImageDownloadManager
//
//  Created by Jeff Mew on 2017-11-11.
//  Copyright © 2017 Jeff Mew. All rights reserved.
//

import Foundation
import UIKit
import PINCache
import PINRemoteImage

typealias FetchImagesCompletionHandler = (_ success: Bool, _ images: [URL: UIImage]?) -> Void

final class ImageDownloadManager {
    
    static let sharedInstance = ImageDownloadManager()
    
    private init() {}
    
    public func fetchImages(imageURLs: [URL], completion: FetchImagesCompletionHandler?) {
        if imageURLs.isEmpty == true {
            completion?(true, nil)
            return
        }
        
        let downloadGroup = DispatchGroup()
        
        var images: [URL: UIImage] = [:]
        
        let _ = DispatchQueue.global(qos: .userInitiated)
        DispatchQueue.concurrentPerform(iterations: imageURLs.count) { [unowned self] i in
            let index = Int(i)
            let url = imageURLs[index]
            downloadGroup.enter()
            cache().containsObject(forKey: url.absoluteString, block: { containsObject in
                if containsObject == true {
                    self.imagesQueue.async(flags: .barrier) {
                        let imageFromCache = self.cache().object(forKey: url.absoluteString)
                        
                        if let imageFromCache = imageFromCache as? Data,
                            let storedImage = UIImage(data: imageFromCache) {
                            images[url] = storedImage
                        }
                        
                        if let imageFromCache = imageFromCache as? UIImage {
                            images[url] = imageFromCache
                        }
                        downloadGroup.leave()
                    }
                    
                } else {
                    let uuid = PINRemoteImageManager.shared().downloadImage(with: url, completion: { result in
                        self.imagesQueue.async(flags: .barrier) {
                            if result.image != nil {
                                images[url] = result.image
                            }
                        }
                        
                        self.activeDownloadsQueue.async(flags: .barrier) {
                            if let resultUUID = result.uuid,
                                let activeDownloadsIndex = self.activeDownloads.index(of: resultUUID) {
                                self.activeDownloads.remove(at: activeDownloadsIndex)
                            }
                        }
                        
                        downloadGroup.leave()
                    })
                    
                    if let uuid = uuid {
                        self.activeDownloadsQueue.async(flags: .barrier) { [unowned self] in
                            self.activeDownloads.append(uuid)
                        }
                    }
                }
            })
        }
        
        downloadGroup.notify(queue: DispatchQueue.main) {
            
            completion?(true, images)
        }
    }
    
    //MARK: Accessors
    
    private lazy var activeDownloads: [UUID] = {
        let activeDownloads = [UUID]()
        return activeDownloads
    }()
    
    //To manage thread safety for activeDownloads
    private let activeDownloadsQueue = DispatchQueue(label: "activeDownloadsQueue", attributes: .concurrent)
    
    //To manage thread safety for images dictionary
    private let imagesQueue = DispatchQueue(label: "imagesQueue", attributes: .concurrent)
    
    private func cache() -> PINCache {
        return PINRemoteImageManager.shared().cache
    }
    
    public func cancelAllActiveDownloads() {
        activeDownloadsQueue.async(flags: .barrier) {
            for activeDownloadUUID in self.activeDownloads {
                PINRemoteImageManager.shared().cancelTask(with: activeDownloadUUID)
            }
        }
    }
    
    //MARK: Cache Control
    
    public func setCacheLimit() {
        cache().memoryCache.costLimit = UInt(600 * 600 * UIScreen.main.scale)
    }
    
    public func clearAllCache() {
        cache().removeAllObjects()
    }
    
    public func clearDiskCache() {
        cache().diskCache.removeAllObjects()
    }
    
    public func clearMemoryCache() {
        cache().memoryCache.removeAllObjects()
    }
}
