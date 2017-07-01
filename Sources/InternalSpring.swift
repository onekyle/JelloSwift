//
//  InternalSpring.swift
//  JelloSwift
//
//  Created by Luiz Fernando Silva on 07/08/14.
//  Copyright (c) 2014 Luiz Fernando Silva. All rights reserved.
//

/// Represents an internal spring inside a soft body object, and keeps points
/// close together
public struct InternalSpring {
    
    /// First point-mass of the spring.
    /// It's contained in the same body as `pointMassB`.
    public let pointMassA: Int
    
    /// Second point-mass of the spring.
    /// It's contained in the same body as `pointMassA`.
    public let pointMassB: Int
    
    /// Rest distance of the spring, or the distance the spring tries to
    /// maintain
    public var restDistance: RestDistance = 0
    
    /// Rest distance of the spring, or the distance the spring tries to
    /// maintain
    public var distance: JFloat {
        get {
            return restDistance.maximumDistance
        }
        set {
            restDistance = .fixed(newValue)
        }
    }
    
    /// The spring coefficient
    public var coefficient: JFloat = 0
    
    /// The spring damping
    public var damping: JFloat = 0
    
    @available(*, deprecated, message: "Use self.init(_:PointMass,_:PointMass,_:RestDistance,_:JFloat,_:JFloat) instead")
    public init(_ pmA: Int, _ pmB: Int, _ distance: JFloat = 0,
                _ springK: JFloat, _ springD: JFloat) {
        pointMassA = pmA
        pointMassB = pmB
        self.distance = distance
        coefficient = springK
        damping = springD
    }
    
    public init(_ pmA: Int, _ pmB: Int, _ distance: RestDistance = 0,
                _ springK: JFloat, _ springD: JFloat) {
        pointMassA = pmA
        pointMassB = pmB
        self.restDistance = distance
        coefficient = springK
        damping = springD
    }
}
