//
//  HDError.swift
//  
//
//  Created by 成殿 on 2022/5/20.
//

import Foundation

public enum HDError: Error, Equatable {
    case invalidTitle
    case invalidUrlString
    case titleExistsButUrlNotSame
    case URLExistsButTitleNotSame
    case taskHaveDone
    case waiting
    case downloadError(description: String)
}
