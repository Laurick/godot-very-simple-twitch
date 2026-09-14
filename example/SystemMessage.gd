class_name VSTSystemMessage extends HBoxContainer

func set_system_msg(type:String , data:Dictionary):
	$RichTextLabel.text = "%s %s" %[type, str(data)]
	queue_sort()
