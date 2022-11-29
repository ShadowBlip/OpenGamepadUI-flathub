extends Store

var store_items: Array = []

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super()
	print("FlatHub Store loaded")


func load_home():
	var http: HTTPRequest = $PopularHTTP
	if http.request("https://flathub.org/api/v1/apps/collection/popular") != OK:
		push_error("Load home request failed")


func _on_popular_http_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	var json: JSON = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		push_error("Unable to parse JSON from response")
		return
	var response = json.get_data()
	print(response)
	
	# Build the store items to send when home is loaded
	store_items = []
	var store_images: Array = []
	for entry in response:
		var item: StoreItem = StoreItem.new()
		item.id = entry["flatpakAppId"]
		item.name = entry["name"]
		if entry["iconDesktopUrl"] != null:
			item.image = entry["iconDesktopUrl"]
		if entry["iconMobileUrl"] != null:
			item.image = entry["iconMobileUrl"]
		store_items.push_back(item)
		
		# Store the image URLs to download them
		store_images.push_back(item.image)
	
	# Fetch all the images to populate our store item entries. This will
	# trigger _on_image_http_request_completed when it is done.
	var image_downloader: MultiHTTPRequest = $ImageHTTP
	if image_downloader.request(store_images) != OK:
		push_error("Error making http request for images")


func _on_image_http_request_completed(results: Array) -> void:
	var i: int = 0
	for response in results:
		var result: int = response["result"]
		var response_code: int = response["response_code"]
		var headers: PackedStringArray = response["headers"]
		var body: PackedByteArray = response["body"]
		
		#result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray
		if result != HTTPRequest.RESULT_SUCCESS:
			push_error("Image couldn't be downloaded. Try a different image.")

		var image = Image.new()
		var error = image.load_png_from_buffer(body)
		if error != OK:
			push_error("Couldn't load the image.")

		var texture = ImageTexture.create_from_image(image)
		var store_item: StoreItem = store_items[i]
		store_item.texture = texture
		
		i += 1
		
	home_loaded.emit(store_items)
