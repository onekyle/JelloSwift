//
//  DemoView.swift
//  JelloSwift
//
//  Created by Luiz Fernando Silva on 14/02/17.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import UIKit
import JelloSwift
import simd

// Note: This view is only implemented for testing purposes - in a real use case you'd probably
// want to use this library along with a proper hardware-accelerated rendering library.

class DemoView: UIView, CollisionObserver
{
    var context: OpenGLContext!
    
    override class var layerClass : AnyClass {
        // In order for our view to display OpenGL content, we need to set it's
        //   default layer to be a CAEAGLayer
        return CAEAGLLayer.self
    }
    
    /// OpenGL VAO for the objects on screen
    var bufferVertices: [VertexBuffer] = []
    
    /// Main OpenGL VAO in which all bodies will be rendered on
    var vao: VertexArrayObject = VertexArrayObject(vao: 0, buffer: VertexBuffer())
    
    var viewportMatrix = Vector2.matrix(scalingBy: 1.0 / (renderingScale / 2), translatingBy: renderingOffset)
    
    var world = World()
    var timer: CADisplayLink! = nil
    
    var updateLabelStopwatch = Stopwatch(startTime: 0)
    var renderLabelStopwatch = Stopwatch(startTime: 0)
    var intervals: [CFAbsoluteTime] = []
    
    let updateInterval = 0.5
    
    var inputMode = InputMode.dragBody
    
    // The current point being dragged around
    var draggingPoint: PointMass? = nil
    
    // The location of the user's finger, in physics world coordinates
    var fingerLocation = Vector2.zero
    
    var physicsTimeLabel: UILabel
    var renderTimeLabel: UILabel
    
    /// A semaphore for accessing the world object.
    /// Used to dispatch update loop in a different thread, and synchronize on rendering
    var worldSemaphore: DispatchSemaphore = DispatchSemaphore(value: 1)
    
    /// Whether to perform a detailed render of the scene. Detailed rendering
    /// renders, along with the body shape, the body's normals, global shape and axis
    var useDetailedRender = true
    
    var collisions: [BodyCollisionInformation] = []
    
    override init(frame: CGRect)
    {
        physicsTimeLabel = UILabel()
        renderTimeLabel = UILabel()
        
        super.init(frame: frame)
        
        initLabels()
        
        // Do any additional setup after loading the view.
        timer = CADisplayLink(target: self, selector: #selector(DemoView.gameLoop))
        timer.add(to: RunLoop.main, forMode: RunLoopMode.defaultRunLoopMode)
        
        initializeLevel()
        
        viewportMatrix = Vector2.matrix(scalingBy: 1.0 / renderingScale)
        
        renderingOffset = Vector2(300, frame.size.height)
        renderingScale = Vector2(renderingScale.x, -renderingScale.y)
        
        isOpaque = false
        
        world.collisionObserver = self
        
        initOpenGL()
    }
    
    required init?(coder aDecoder: NSCoder)
    {
        physicsTimeLabel = UILabel()
        renderTimeLabel = UILabel()
        
        super.init(coder: aDecoder)
        
        initLabels()
        
        initOpenGL()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        context.resetContext()
        
        physicsTimeLabel.frame = CGRect(x: 20, y: 20, width: self.bounds.width - 40, height: 20)
        renderTimeLabel.frame = CGRect(x: 20, y: 37, width: self.bounds.width - 40, height: 20)
    }
    
    func initOpenGL() {
        layer.isOpaque = true
        
        context = OpenGLContext(layer: layer as! CAEAGLLayer)
        
        vao = context.generateVAO()
    }
    
    func initLabels()
    {
        physicsTimeLabel.frame = CGRect(x: 20, y: 20, width: 500, height: 20)
        renderTimeLabel.frame = CGRect(x: 20, y: 37, width: 500, height: 20)
        
        addSubview(physicsTimeLabel)
        addSubview(renderTimeLabel)
    }
    
    func initializeLevel()
    {
        let size = frame.size
        
        // Create basic shapes
        let vec = toWorldCoords(Vector2(size.width, 400) / 2)
        
        createBouncyBall(vec)
        
        for i in 0..<6
        {
            let v = vec + Vector2(CGFloat(i - 3), CGFloat(2 + i * 1))
            
            createBouncyBall(v)
        }
        
        // Create a few pinned bodies
        let pb1 = createBouncyBall(toWorldCoords(Vector2(size.width * 0.2, size.height / 2)), pinned: true, radius: 3)
        let pb2 = createBouncyBall(toWorldCoords(Vector2(size.width * 0.8, size.height / 2)), pinned: true, radius: 3)
        pb1.component(ofType: SpringComponent.self)?.setShapeMatchingConstants(200, 10)
        pb2.component(ofType: SpringComponent.self)?.setShapeMatchingConstants(200, 10)
        
        // Create some free boxes around the level
        createBox(toWorldCoords(Vector2(size.width / 2, size.height / 3)), size: Vector2.unit)
        createBox(toWorldCoords(Vector2(size.width * 0.4, size.height / 3)), size: Vector2.unit)
        let box3 = createBox(toWorldCoords(Vector2(size.width * 0.6, size.height / 3)), size: Vector2.unit)
        
        // Lock the rotation of the third box
        box3.freeRotate = false
        
        // Create a pinned box in the middle of the level
        let pinnedBox = createBox(toWorldCoords(Vector2(size.width / 2, size.height / 2)), size: Vector2.unit, pinned: true)
        // Increase the velocity damping of the pinned box so it doesn't jiggles around nonstop
        pinnedBox.velDamping = 0.99
        
        // Create two kinematic boxes
        createBox(toWorldCoords(Vector2(size.width * 0.3, size.height / 2)), size: Vector2(2, 2), kinematic: true)
        createBox(toWorldCoords(Vector2(size.width * 0.7, size.height / 2)), size: Vector2(2, 2), kinematic: true)
        
        // Create a few structures to showcase the joints feature
        createLinkedBouncyBalls(toWorldCoords(Vector2(size.width / 2, size.height * 0.65)))
        
        createBallBoxLinkedStructure(toWorldCoords(Vector2(size.width * 0.8, size.height * 0.8)))
        createScaleStructure(toWorldCoords(Vector2(size.width * 0.4, size.height * 0.8)))
        
        createCarStructure(toWorldCoords(Vector2(size.width * 0.12, 90)))
        createBox(toWorldCoords(Vector2(size.width * 0.5, 16)), size: Vector2(17, 0.5), isStatic: true)
        
        // Create the ground box
        var box = ClosedShape()
        box.begin()
        box.addVertex(Vector2(-10,   1))
        box.addVertex(Vector2( 0,  0.6)) // A little inward slope
        box.addVertex(Vector2( 10,   1))
        box.addVertex(Vector2( 10,  -1))
        box.addVertex(Vector2(-10,  -1))
        box.finish()
        
        let platform = Body(world: world, shape: box, pointMasses: [CGFloat.infinity], position: toWorldCoords(Vector2(size.width / 2, 150)))
        platform.isStatic = true
    }
    
    // MARK: - Touch
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?)
    {
        /* Called when a touch begins */
        if(inputMode == InputMode.createBall)
        {
            for touch: AnyObject in touches
            {
                let location = touch.location(in: self)
                
                let vecLoc = toWorldCoords(Vector2(location.x, location.y))
                
                createBouncyBall(vecLoc)
            }
        }
        else if(inputMode == InputMode.dragBody)
        {
            // Select the closest point-mass to drag
            let touch: UITouch = touches.first!
            let location = touch.location(in: self)
            fingerLocation = toWorldCoords(Vector2(location.x, location.y))
            
            var closest: PointMass? = nil
            var closestD = CGFloat.greatestFiniteMagnitude
            
            for body in world.bodies
            {
                for p in body.pointMasses
                {
                    let dist = p.position.distance(to: fingerLocation)
                    if(closest == nil || dist < closestD)
                    {
                        closest = p
                        closestD = dist
                    }
                }
            }
            
            draggingPoint = closest
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?)
    {
        let touch: AnyObject = touches.first!
        let location = touch.location(in: self)
        fingerLocation = toWorldCoords(Vector2(location.x, location.y))
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?)
    {
        // Reset dragging point
        draggingPoint = nil
    }
    
    // MARK: - Drawing
    
    func drawLine(from start: Vector2, to end: Vector2, color: UInt = 0xFFFFFFFF) {
        
        let normal = (start - end).normalized().perpendicular() / 15
        
        var buffer = VertexBuffer()
        
        buffer.addVertex(start + normal / 2, color: color)
        buffer.addVertex(end + normal / 2, color: color)
        buffer.addVertex(end - normal / 2, color: color)
        buffer.addVertex(start - normal / 2, color: color)
        
        buffer.addTriangleAtIndexes(0, 1, 2)
        buffer.addTriangleAtIndexes(2, 3, 0)
        
        bufferVertices.append(buffer)
    }
    
    func drawPolyOutline(_ points: [Vector2], color: UInt = 0xFFFFFFFF) {
        guard var last = points.last else {
            return
        }
        
        for point in points {
            drawLine(from: point, to: last, color: color)
            last = point
        }
    }
    
    func render()
    {  
        let sw = Stopwatch.startNew()
        
        world.joints.forEach(drawJoint)
        world.bodies.forEach(drawBody)
        
        drawDrag()
        
        if(useDetailedRender)
        {
            // Draw collisions
            for info in collisions
            {
                let pointB = info.hitPt
                let normal = info.normal
                
                drawLine(from: pointB, to: pointB + normal / 4, color: 0xFFFF0000)
            }
        }
        
        collisions.removeAll(keepingCapacity: true)
        
        renderOpenGL()
        
        if let duration = renderLabelStopwatch.duration, duration > updateInterval
        {
            renderLabelStopwatch.reset()
            
            let time = round(sw.stop() * 1000 * 20) / 20
            let fps = 1000 / time
                                                            //  VVVVVV  AIN'T GOT NO TIME TO DYNAMICALLY ALIGN, BABEY!
            renderTimeLabel.text = String(format: "Render time:              %0.2lfms (%0.0lffps)", time, fps)
        }
    }
    
    // MARK: - Update Loop (CADisplayLink)
    
    func gameLoop()
    {
        update()
        render()
    }
    
    func update()
    {
        let sw = Stopwatch()
        
        updateWithTimeSinceLastUpdate(timer.timestamp)
        
        let time = sw.stop() * 1000
        
        intervals.append(time)
        if(intervals.count > 200) {
            intervals = Array(intervals.dropFirst(intervals.count - 200))
        }
        
        if let duration = updateLabelStopwatch.duration, duration > updateInterval
        {
            updateLabelStopwatch.reset()
            
            let timeMilli = time
            let timeMilliRounded = round(timeMilli * 100) / 100
            let fps = 1000 / timeMilliRounded
            
            let avgMilli = intervals.reduce(0, +) / CFAbsoluteTime(intervals.count)
            let avgMilliRounded = round(avgMilli * 100) / 100
            
            DispatchQueue.main.async {
                self.physicsTimeLabel.text = String(format: "Physics update time: %0.2lfms (%0.0lffps) Avg time (last \(self.intervals.count) frames): %0.2lfms", timeMilliRounded, fps, avgMilliRounded)
            }
        }
    }
    
    func updateWithTimeSinceLastUpdate(_ timeSinceLast: CFTimeInterval)
    {
        /* Called before each frame is rendered */
        updateDrag()
        
        // Update the physics world
        for _ in 0..<5 {
            self.world.update(1.0 / 200)
        }
    }
    
    // Updates the dragging functionality
    func updateDrag()
    {
        // Dragging point
        guard let p = draggingPoint , inputMode == InputMode.dragBody else {
            return
        }
        
        let dragForce = calculateSpringForce(posA: p.position, velA: p.velocity, posB: fingerLocation, velB: Vector2.zero, distance: 0, springK: 700, springD: 20)
        
        p.applyForce(of: dragForce)
    }
    
    func bodiesDidCollide(_ info: BodyCollisionInformation)
    {
        collisions.append(info)
    }
    
    func bodyCollision(_ info: BodyCollisionInformation, didExceedPenetrationThreshold penetrationThreshold: CGFloat) {
        print("penetration above Penetration Threshold!!  penetration = \(info.penetration), threshold = \(penetrationThreshold), difference = \(info.penetration-penetrationThreshold)")
    }
    
    // MARK: - Rendering Utils
    
    /// Renders the dragging shape line
    func drawDrag()
    {
        // Dragging point
        guard let p = draggingPoint , inputMode == InputMode.dragBody else {
            return
        }
        
        // Create the path to draw
        let lineStart = p.position
        let lineEnd = fingerLocation
        
        drawLine(from: lineStart, to: lineEnd, color: 0xFF00DD00)
    }
    
    func drawJoint(_ joint: BodyJoint)
    {
        let start = joint.bodyLink1.position
        let end = joint.bodyLink2.position
        
        drawLine(from: start, to: end, color: joint.enabled ? 0xFFEEEEEE : 0xFFCCCCCC)
    }
    
    func drawBody(_ body: Body)
    {
        // Triangulate body's polygon
        guard let (vertices, indices) = LibTessTriangulate.process(polygon: body.vertices) else {
            return
        }
        
        var bodyBuffer = VertexBuffer()
        
        for vert in vertices {
            bodyBuffer.addVertex(x: vert.x, y: vert.y)
        }
        
        // Add vertex index triplets
        for i in 0..<indices.count / 3 {
            bodyBuffer.addTriangleAtIndexes(indices[i * 3], indices[i * 3 + 1], indices[i * 3 + 2])
        }
        
        bodyBuffer.setVerticesColor(0x7DFFFFFF)
        
        let shapePoints = body.vertices
        
        if(!useDetailedRender)
        {
            // Don't do any other rendering other than the body's buffer
            bufferVertices.append(bodyBuffer)
            return
        }
        
        // Draw normals, for pressure bodies
        if body.component(ofType: PressureComponent.self) != nil
        {
            for (i, normal) in body.pointNormals.enumerated()
            {
                let p = shapePoints[i]
                
                drawLine(from: p, to: p + normal / 3, color: 0xFFEC33EC)
            }
        }
        
        // Draw the body's global shape
        drawPolyOutline(body.globalShape, color: 0xFF777777)
        
        // Draw lines going from the body's outer points to the global shape indices
        for (globalShape, p) in zip(body.globalShape, shapePoints)
        {
            let start = p
            let end = globalShape
            
            drawLine(from: start, to: end, color: 0xFF449944)
        }
        
        // Draw the body now
        
        bufferVertices.append(bodyBuffer)
        drawPolyOutline(shapePoints, color: 0xFF000000)
        
        //polyDrawer.queuePoly(points, fillColor: 0xADFFFFFF, strokeColor: 0xFF000000)
        
        // Draw the body axis
        let axisUp    = [body.derivedPos, body.derivedPos + Vector2(0, 0.6).rotated(by: body.derivedAngle)]
        let axisRight = [body.derivedPos, body.derivedPos + Vector2(0.6, 0).rotated(by: body.derivedAngle)]
        
        // Rep Up vector
        drawLine(from: axisUp[0], to: axisUp[1], color: 0xFFED0000)
        // Green Right vector
        drawLine(from: axisRight[0], to: axisRight[1], color: 0xFF00ED00)
    }
    
    // MARK: - Helper body creation methods
    
    /// Creates a box at the specified world coordinates with the specified size
    @discardableResult
    func createBox(_ pos: Vector2, size: Vector2, pinned: Bool = false, kinematic: Bool = false, isStatic: Bool = false, angle: CGFloat = 0, mass: CGFloat = 0.5) -> Body
    {
        // Create the closed shape for the box's physics body
        let shape = ClosedShape
                        .rectangle(ofSize: size)
                        .transformedBy(rotatingBy: angle)
        
        var comps = [BodyComponentCreator]()
        
        // Add a spring body component - spring bodies have string physics that attract the inner points, it's one of the
        // forces that holds a body together
        comps.append(SpringComponentCreator(shapeMatchingOn: true, edgeSpringK: 600, edgeSpringDamp: 20, shapeSpringK: 100, shapeSpringDamp: 60))
        
        if(!pinned)
        {
            // Add a gravity component that will pull the body down
            comps.append(GravityComponentCreator())
        }
        
        let body = Body(world: world, shape: shape, pointMasses: [isStatic ? CGFloat.infinity : mass], position: pos, kinematic: kinematic, components: comps)
        body.isPined = pinned
        
        // In order to have the box behave correctly, we need to add some internal springs to the body
        let springComp = body.component(ofType: SpringComponent.self)
        
        // The two first arguments are the indexes of the point masses to link, the next two are the spring constants,
        // and the last one is the distance the spring will try to mantain the two point masses at.
        // Specifying the distance as -1 sets it as the current distance between the specified point masses
        springComp?.addInternalSpring(body, pointA: 0, pointB: 2, springK: 100, damping: 10, dist: nil)
        springComp?.addInternalSpring(body, pointA: 1, pointB: 3, springK: 100, damping: 10, dist: nil)
        
        return body
    }
    
    /// Creates a bouncy ball at the specified world coordinates
    @discardableResult
    func createBouncyBall(_ pos: Vector2, pinned: Bool = false, kinematic: Bool = false, radius: CGFloat = 1, mass: CGFloat = 0.5, def: Int = 12) -> Body
    {
        // Create the closed shape for the ball's physics body
        let shape = ClosedShape
                        .circle(ofRadius: radius, pointCount: def)
                        .transformedBy(scalingBy: Vector2(0.3, 0.3))
        
        var comps = [BodyComponentCreator]()
        
        // Add a spring body component - spring bodies have string physics that attract the inner points, it's one of the
        // forces that holds a body together
        comps.append(SpringComponentCreator(shapeMatchingOn: true, edgeSpringK: 600, edgeSpringDamp: 20, shapeSpringK: 10, shapeSpringDamp: 20))
        
        // Add a pressure component - pressure applies an outwards-going force that basically
        // tries to expand the body as if filled with air, like a balloon
        comps.append(PressureComponentCreator(gasAmmount: 90))
        
        // Add a gravity component taht will pull the body down
        comps.append(GravityComponentCreator())
        
        let body = Body(world: world, shape: shape, pointMasses: [mass], position: pos, kinematic: kinematic, components: comps)
        
        body.isPined = pinned
        
        return body
    }
    
    /// Creates two linked bouncy balls in a given position in the world
    func createLinkedBouncyBalls(_ pos: Vector2)
    {
        let b1 = createBouncyBall(pos - Vector2(1, 0), pinned: false, kinematic: false, radius: 1)
        let b2 = createBouncyBall(pos + Vector2(1, 0), pinned: false, kinematic: false, radius: 1)
        
        // Create the joint links
        let l1 = BodyJointLink(body: b1)
        let l2 = BodyJointLink(body: b2)
        
        world.addJoint(SpringBodyJoint(on: world, link1: l1, link2: l2, coefficient: 100, damping: 20))
    }
    
    /// Creates a pinned box with a ball attached to one of its edges
    func createBallBoxLinkedStructure(_ pos: Vector2)
    {
        let b1 = createBouncyBall(pos - Vector2(0, 2), pinned: false, kinematic: false, radius: 1, mass: 1)
        let b2 = createBox(pos, size: Vector2.unit, pinned: true, kinematic: false, mass: 1)
        
        // Create the joint links
        let l1 = BodyJointLink(body: b1)
        let l2 = EdgeJointLink(body: b2, edgeIndex: 2, edgeRatio: 0.5)
        
        world.addJoint(SpringBodyJoint(on: world, link1: l1, link2: l2, coefficient: 100, damping: 20))
    }
    
    /// Creates a pinned box with two balls attached to one of its edges
    func createScaleStructure(_ pos: Vector2)
    {
        let b1 = createBox(pos, size: Vector2(2, 1), pinned: true, kinematic: false)
        let b2 = createBouncyBall(pos + Vector2(-1.2, -2), pinned: false, kinematic: false, radius: 1)
        let b3 = createBouncyBall(pos + Vector2( 1.2, -2), pinned: false, kinematic: false, radius: 1)
        
        // Create the joints that link the box with the left sphere
        let l1 = BodyJointLink(body: b2)
        let l2 = EdgeJointLink(body: b1, edgeIndex: 2, edgeRatio: 0.8)
        
        // Create the joints that link the box with the right sphere
        let l3 = BodyJointLink(body: b3)
        let l4 = EdgeJointLink(body: b1, edgeIndex: 2, edgeRatio: 0.2)
        
        // Create the joints
        let joint1 = SpringBodyJoint(on: world, link1: l1, link2: l2, coefficient: 10, damping: 2)
        let joint2 = SpringBodyJoint(on: world, link1: l3, link2: l4, coefficient: 40, damping: 5)
        
        joint2.restDistance = joint2.restDistance.minimumDistance...joint2.restDistance.minimumDistance + 2
        
        // Enable collision between the bodies
        joint1.allowCollisions = true
        joint2.allowCollisions = true
        
        world.addJoint(joint1)
        world.addJoint(joint2)
    }
    
    /// Creates a car structure
    func createCarStructure(_ pos: Vector2)
    {
        var carShape = ClosedShape()
        
        // Add the car shape vertices
        carShape.begin()
        
        // Points created in an external editor tool
        carShape.addVertex(x: -0.7937825232354604, y: -0.30250560258972364)
        carShape.addVertex(x: -1.336418182150189,  y: 0.09174228082403624)
        carShape.addVertex(x: -2.007152743584187,  y: 0.09174228082403624)
        carShape.addVertex(x: -2.549788402498916,  y: -0.30250560258972364)
        carShape.addVertex(x: -2.7570567806966455, y: -0.9404120779458979)
        carShape.addVertex(x: -4.144927650095719,  y: -0.9404120779458979)
        carShape.addVertex(x: -4.144927650095719,  y: 0.4418818905641408)
        carShape.addVertex(x: -2.982614013609058,  y: 1.4496338285486368)
        carShape.addVertex(x: -1.2336781172394489, y: 1.8443237218438626)
        carShape.addVertex(x: 1.2758186165123433,  y: 1.8443237218438626)
        carShape.addVertex(x: 3.1062068496621604,  y: 0.6077200296906478)
        carShape.addVertex(x: 4.693548953434301,   y: 0.29764251031080285)
        carShape.addVertex(x: 4.422231123976936,   y: -0.9404120779458979)
        carShape.addVertex(x: 2.59178042860568,    y: -0.9404120779458979)
        carShape.addVertex(x: 2.3845120315923336,  y: -0.3025056116022918)
        carShape.addVertex(x: 1.8418764096417257,  y: 0.09174231580466982)
        carShape.addVertex(x: 1.1711418119107195,  y: 0.09174231580466982)
        carShape.addVertex(x: 0.6285061899601116,  y: -0.3025056116022918)
        carShape.addVertex(x: 0.42123779294676533, y: -0.9404120779458979)
        carShape.addVertex(x: -0.5865141450377307, y: -0.9404120779458979)
        
        // Scale down
        carShape.transformOwnBy(scalingBy: Vector2(0.65, 0.65))
        carShape.finish(recentering: true)
        
        let bodyOffset = Vector2(0, 0.4)
        
        let carBody = Body(world: world, shape: carShape, pointMasses: [0.7], position: pos + bodyOffset, components: [SpringComponentCreator(shapeMatchingOn: true, edgeSpringK: 300, edgeSpringDamp: 30, shapeSpringK: 600, shapeSpringDamp: 30), GravityComponentCreator()])
        
        let leftWheel  = createBouncyBall(carBody.derivedPos + Vector2.rotate(Vector2(-1.1, -0.5) - bodyOffset, by: carBody.derivedAngle), pinned: false, kinematic: false, radius: 0.5, mass: 0.5)
        let rightWheel = createBouncyBall(carBody.derivedPos + Vector2.rotate(Vector2( 1.1, -0.5) - bodyOffset, by: carBody.derivedAngle), pinned: false, kinematic: false, radius: 0.5, mass: 0.5)
        
        // Create the left wheel constraint
        let ljWheel = BodyJointLink(body: leftWheel)
        let ljCar = ShapeJointLink(body: carBody, pointMassIndexes: [19, 0, 1, 2, 3, 4])
        ljCar.offset = Vector2(0, -0.6)
        
        let leftJoint = SpringBodyJoint(on: world, link1: ljWheel, link2: ljCar, coefficient: 100, damping: 15, distance: 0.0)
        leftJoint.allowCollisions = true
        
        let rjWheel = BodyJointLink(body: rightWheel)
        let rjCar = ShapeJointLink(body: carBody, pointMassIndexes: [13, 14, 15, 16, 17, 18])
        rjCar.offset = Vector2(0, -0.6)
        
        let rightJoint = SpringBodyJoint(on: world, link1: rjWheel, link2: rjCar, coefficient: 100, damping: 15, distance: 0.0)
        rightJoint.allowCollisions = true
        
        world.addJoint(leftJoint)
        world.addJoint(rightJoint)
    }
    
    /// Enum used to modify the input mode of the test simulation
    enum InputMode: Int
    {
        /// Creates a jiggly ball under the finger on tap
        case createBall
        /// Allows dragging bodies around
        case dragBody
    }
}

extension DemoView {
    
    ///                                               1
    /// Returns a 3x3 matrix for projecting into a -1 0 1 -style space such that
    ///                                              -1
    /// a [0, 0] vector projects into the top-left (1, -1), and [width, height]
    /// projects into the bottom-right (-1, 1).
    ///
    func matrixForOrthoProjection(width: CGFloat, height: CGFloat) -> Vector2.NativeMatrixType {
        let size = Vector2(width, height)
        let scaledSize = Vector2(1 / width, -1 / height) * 2
        
        let matrix = Vector2.matrix(translatingBy: -size / 2)
        return matrix * Vector2.matrix(scalingBy: scaledSize)
    }
    
    func renderOpenGL() {
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), context.sampleFramebuffer)
        
        glClearColor(0.7, 0.7, 0.7, 1.0)
        glClear(GLbitfield(Int(GL_COLOR_BUFFER_BIT) | Int(GL_DEPTH_BUFFER_BIT)))
        
        // Adjust viewport by the aspect ratio
        let viewportMatrix = matrixForOrthoProjection(width: bounds.size.width, height: bounds.size.height)
        
        // Apply transformation matrix
        let matrix = viewportMatrix.glFloatMatrix4x4()
        
        let matrixSlot = context.transformMatrixSlot
        glUniformMatrix4fv(GLint(matrixSlot), 1, GLboolean(0), matrix)
        
        glViewport(0, 0, GLint(bounds.size.width), GLint(bounds.size.height))
        
        vao.buffer.clearVertices()
        
        // Matrix to transform JelloSwift's coordinates into proper coordinates
        // for OpenGL
        let mat = Vector2.matrix(scalingBy: renderingScale, rotatingBy: 0, translatingBy: renderingOffset).matrix4x4()
        
        /// Merge buffers
        for buffer in bufferVertices {
            // Convert point to screen coordinates
            var buffer = buffer
            buffer.applyTransformation(mat)
            
            vao.buffer.merge(with: buffer)
        }
        
        // Update VAO before rendering
        context.updateVAO(for: vao)
        
        glBindVertexArrayOES(vao.vao)
        
        glDrawElements(GLenum(GL_TRIANGLES), GLsizei(vao.buffer.indices.count), GLenum(GL_UNSIGNED_INT), nil)
        
        glBindFramebuffer(GLenum(GL_DRAW_FRAMEBUFFER_APPLE), context.frameBuffer)
        glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER_APPLE), context.sampleFramebuffer)
        
        glResolveMultisampleFramebufferAPPLE()
        
        let discards: [GLenum] = [ GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_DEPTH_ATTACHMENT) ]
        glDiscardFramebufferEXT(GLenum(GL_READ_FRAMEBUFFER_APPLE), 2, discards)
        
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), context.colorRenderBuffer)
        
        context.context.presentRenderbuffer(Int(GL_RENDERBUFFER))
        
        glBindVertexArrayOES(0)
        
        bufferVertices.removeAll(keepingCapacity: true)
    }
}

extension Vector2.NativeMatrixType {
    
    /// Returns a 4x4 GLfloat matrix representation for this matrix object
    func glFloatMatrix4x4() -> [GLfloat] {
        var matrix: [GLfloat] = [GLfloat](repeating: 0, count: 16)
        
        matrix[0] = GLfloat(cmatrix.columns.0.x)
        matrix[4] = GLfloat(cmatrix.columns.0.y)
        matrix[12] = GLfloat(cmatrix.columns.0.z)
        
        matrix[1] = GLfloat(cmatrix.columns.1.x)
        matrix[5] = GLfloat(cmatrix.columns.1.y)
        matrix[13] = GLfloat(cmatrix.columns.1.z)
        
        matrix[2] = GLfloat(cmatrix.columns.2.x)
        matrix[6] = GLfloat(cmatrix.columns.2.y)
        matrix[14] = GLfloat(cmatrix.columns.2.z)
        
        matrix[15] = 1
        
        return matrix
    }
    
    /// Returns a 4x4 floating-point transformation matrix for this matrix
    /// object
    func matrix4x4() -> float4x4 {
        var matrix = float4x4(diagonal: [1, 1, 1, 1])
        
        matrix[0] = float4(x: self[0, 0], y: self[0, 1], z: 0, w: self[0, 2])
        matrix[1] = float4(x: self[1, 0], y: self[1, 1], z: 0, w: self[1, 2])
        matrix[2] = float4(x: self[2, 0], y: self[2, 1], z: 1, w: self[2, 2])
        matrix[3] = float4(x: 0, y: 0, z: 0, w: 1)
        
        return matrix
    }
}
