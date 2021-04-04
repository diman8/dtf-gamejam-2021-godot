extends CSGBox

onready var collision_shape : CollisionShape = $StaticBody/CollisionShape

func _ready():
	collision_shape.shape = BoxShape.new()
	collision_shape.shape.extents = Vector3(width / 2, height / 2, depth / 2) 
