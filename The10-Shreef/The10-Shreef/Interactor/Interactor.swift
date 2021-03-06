//
//  Interactor.swift
//  The10-Shreef
//
//  Created by Shreef Hagazi  on 2/12/19.
//  Copyright © 2019 Shreef Hagazi . All rights reserved.
//

import TMDBSwift
import CoreData

protocol FetchOrCreate: class, HasId {
    associatedtype T: NSManagedObject, HasId
}

protocol HasId {
    var id: String { get set }
}

extension FetchOrCreate {
    static func fetchOrCreate(with ID: String) -> T {
        if let object = fetch(with: ID) {
            return object
        }
        else {
            var object = createNew()
            object.id = ID
            return object
        }
    }
    
    static func createNew() -> T {
        let className = String(describing: type(of: self)).split(separator:".").first ?? ""
        let newT = NSEntityDescription.insertNewObject(forEntityName: String(className), into: CoreDataManager.shared.context) as! T
        return newT
    }
    
    static func fetchObjects(with key: String? = "", with value: String? = "") -> [T] {
        let className = String(describing: type(of: self)).split(separator:".").first ?? ""
        let request = NSFetchRequest<T>(entityName: String(className))
        if let key = key, let value = value {
            request.predicate = NSPredicate(format: "\(key) == %@", value)
        }
        let fetchedObjects = try! CoreDataManager.shared.context.fetch(request)
        return fetchedObjects
    }
    
    static func fetch(with ID: String) -> T? {
        let className = String(describing: type(of: self)).split(separator:".").first ?? ""
        let request = NSFetchRequest<T>(entityName: String(className))
        request.predicate = NSPredicate(format: "id == %@", ID)
        let fetchedObjects = try! CoreDataManager.shared.context.fetch(request)
        if let first = fetchedObjects.first {
            return first
        }
        return nil
    }
    
    static func delete(with ID: String) {
        if let object = fetch(with: ID) {
            CoreDataManager.shared.context.delete(object)
        }
    }
}

class Interactor: NSObject {
    private func fetchTrailers(movieID: Int, completionHandler:  ((Bool?) -> Void)) {
        MovieMDB.videos(movieID: movieID, completion: { (client, trailers) in
            guard let trailers = trailers else { return }
            
            let trailer = Trailer.createNew()
            trailer.parse(client: client, results: trailers)
            
            let movie = Movie.fetch(with: trailer.id)
            movie?.trailer = trailer
        })
        completionHandler(true)
    }
    
    private func fetchImdbID(movieID: Int, completionHandler: @escaping ((Imdb?) -> Void)) {
        MovieMDB.movie(movieID: movieID, completion: { (client, _) in
            let imdb = Imdb.createNew()
            imdb.parse(client: client)
            
            let movie = Movie.fetch(with: imdb.id)
            movie?.imdb = imdb
            completionHandler(imdb)
        })
    }
    
    func fetchMovieData(movieType: String? = "", completionHandler: @escaping (([Movie]) -> Void)) {
        let dispatchGroup = DispatchGroup()
        let objects = Movie.fetchObjects(with: "type", with: movieType)
        objects.forEach({ (movie) in
            dispatchGroup.enter()
            if let movieId = Int(movie.id) {
                fetchTrailers(movieID: movieId, completionHandler: { (_) in
                })
                fetchImdbID(movieID: movieId, completionHandler: { (imdb) in
                    if let imdb = imdb {
                        self.fetchImdb(imdbID: imdb.path, completionHandler: { (data, _) in
                            guard let data = data else { return }
                            imdb.parse(imdbInfo: data)
                            if data.imdbRating == "" || data.imdbRating == "N/A" || imdb.rottenTomatoes == "" {
                                Movie.delete(with: imdb.id)
                            }
                            dispatchGroup.leave()
                        })
                    }
                })
            }
            
        })
        dispatchGroup.notify(queue: .main) {
            completionHandler(objects)
        }
    }
    
    func fetchImdb(imdbID: String, completionHandler: @escaping ((imdbInfo?, Error?) -> Void)) {
        var components          = URLComponents()
        components.scheme       = "https"
        components.host         = "www.omdbapi.com"
        components.queryItems   = [URLQueryItem(name: "i", value: imdbID),
                                   URLQueryItem(name: "apikey", value: "a3a5bcba")]
        
        guard let url = components.url else { return }
        
        URLSession.shared.dataTask(with: url) { (data, response, error) in
            if error != nil {
                print(error!.localizedDescription)
            }
            guard let data = data else { return }
            do {
                let ratingData = try JSONDecoder().decode(imdbInfo.self, from: data)
                completionHandler(ratingData, error)
            } catch let error {
                print(error.localizedDescription)
            }
            }.resume()
    }
    
    func fetchPoster(posterPath: String, completionHandler: @escaping ((UIImage?) -> Void)) {
        var url = URL(string: "https://image.tmdb.org/t/p/w500")!
        url.appendPathComponent(posterPath)
        let data = try? Data(contentsOf: url)
        if let imageData = data {
            let image = UIImage(data: imageData)
            completionHandler(image)
        }
    }
}
