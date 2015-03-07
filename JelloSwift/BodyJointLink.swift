//
//  BodyJointLink.swift
//  JelloSwift
//
//  Created by Luiz Fernando Silva on 06/03/15.
//  Copyright (c) 2015 Luiz Fernando Silva. All rights reserved.
//

import Foundation
import CoreGraphics

/// Represents a joint link that links to a while body
class BodyJointLink: JointLinkType
{
    // Like the PointJointLink, this is a very straightforward implementation, delegating most of the methods to the underlying body object
    
    /// The body that this joint link is linked to
    private var _body: Body;
    
    /// Gets the body that this joint link is linked to
    var body: Body { return _body; }
    
    /// Gets the type of joint this joint link represents
    var linkType: LinkType { return LinkType.Body }
    
    /// Gets the position, in world coordinates, at which this joint links with the underlying body
    var position: Vector2
    {
        return _body.derivedPos;
    }
    
    /// Gets the velocity of the object this joint links to
    var velocity: Vector2
    {
        return _body.derivedVel;
    }
    
    /// Gets the total mass of the subject of this joint link
    var mass: CGFloat
    {
        return _body.pointMasses.reduce(0, combine: { $0 + $1.mass });
    }
    
    /// Gets a value specifying whether the object referenced by this JointLinkType is static
    var isStatic: Bool
    {
        return _body.isStatic || _body.isPined;
    }
    
    /// Inits a new body joint link with the specified parameters
    init(body: Body)
    {
        _body = body;
    }
    
    /// Appies a given force to the subject of this joint link
    ///
    /// :param: force A force to apply to the subjects of this joint link
    func applyForce(force: Vector2)
    {
        _body.addGlobalForce(position, force);
    }
}