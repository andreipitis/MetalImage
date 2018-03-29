//
//  AtomicQueue.swift
//  MetalImage
//
//  Created by Andrei-Sergiu Pițiș on 12/07/2017.
//  Copyright © 2017 Andrei-Sergiu Pițiș. All rights reserved.
//

import Foundation

class AtomicQueue<T> {
    private var items:[T] = []

    private var mutex: pthread_mutex_t = pthread_mutex_t()

    init() {
        pthread_mutex_init(&mutex, nil)
    }

    deinit {
        assert(pthread_mutex_trylock(&mutex) == 0 && pthread_mutex_unlock(&mutex) == 0, "Deinitialization of a locked mutex results in undefined behavior!")
        pthread_mutex_destroy(&mutex)
    }

    func enqueue(item: T) {
        pthread_mutex_lock(&mutex)
        items.append(item)

        pthread_mutex_unlock(&mutex)
    }

    func dequeue() -> T? {
        pthread_mutex_lock(&mutex)

        if let item = items.first {
            items.removeFirst()

            pthread_mutex_unlock(&mutex)
            return item
        }

        pthread_mutex_unlock(&mutex)
        return nil
    }

    func emptyQueue() {
        pthread_mutex_lock(&mutex)
        items.removeAll()

        pthread_mutex_unlock(&mutex)
    }

    func count() -> Int {
        pthread_mutex_lock(&mutex)
    
        let count = items.count

        pthread_mutex_unlock(&mutex)
        return count
    }
}
