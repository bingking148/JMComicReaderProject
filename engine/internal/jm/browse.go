package jm

// Category is a shelf the mobile category API can actually filter.
type Category struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

// Categories are the category ids accepted by /categories/filter.
func Categories() []Category {
	return []Category{
		{ID: "0", Name: "全部"},
		{ID: "doujin", Name: "同人"},
		{ID: "single", Name: "单本"},
		{ID: "short", Name: "短篇"},
		{ID: "hanman", Name: "韩漫"},
		{ID: "meiman", Name: "美漫"},
		{ID: "another", Name: "其他"},
		{ID: "3D", Name: "3D"},
		{ID: "english_site", Name: "英文"},
		{ID: "doujin_cosplay", Name: "Cosplay"},
	}
}

// Discover is the homepage payload: suggested words plus two real shelves.
type Discover struct {
	Keywords      []string   `json:"keywords"`
	Categories    []Category `json:"categories"`
	Latest        []Summary  `json:"latest"`
	MostFavorited []Summary  `json:"mostFavorited"`
}

// NormalizeOrder maps UI names onto the mobile order codes.
func NormalizeOrder(value string) string {
	switch value {
	case "mv", "mp", "tf", "mr":
		return value
	case "views":
		return "mv"
	case "pictures":
		return "mp"
	case "favorites", "likes", "favorites_desc":
		return "tf"
	default:
		return "mr"
	}
}

// NormalizeTime maps UI names onto t/w/m/a.
func NormalizeTime(value string) string {
	switch value {
	case "t", "w", "m", "a":
		return value
	case "today":
		return "t"
	case "week":
		return "w"
	case "month":
		return "m"
	default:
		return "a"
	}
}

// NormalizeCategory keeps only category ids the API lists.
func NormalizeCategory(value string) string {
	switch value {
	case "0", "doujin", "single", "short", "another", "hanman", "meiman", "doujin_cosplay", "3D", "english_site":
		return value
	default:
		return "0"
	}
}

// FilterOrder is the combined code used by /categories/filter.
func FilterOrder(orderBy, timeRange string) string {
	orderBy = NormalizeOrder(orderBy)
	timeRange = NormalizeTime(timeRange)
	if timeRange == "a" {
		return orderBy
	}
	return orderBy + "_" + timeRange
}
