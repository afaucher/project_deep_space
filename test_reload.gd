extends SceneTree
func _init():
    var s = load('res://scripts/ui/contacts_panel.gd')
    if s is GDScript:
        var err = s.reload(false)
        print('Reload returned: ', err)
    quit()
