extends Node

const Asteroid = preload("res://scripts/asteroid.gd")

func _ready():
	var ast = Asteroid.new()
	var sig = ast.get_signature()
	print("Asteroid signature: ", sig)
	get_tree().quit()
