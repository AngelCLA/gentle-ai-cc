// gentle-cc is the standalone Command Code companion router.
package main

import (
	"os"

	"gentle-cc/internal/wrapper"
)

func main() {
	os.Exit(wrapper.Main(os.Args[1:]))
}
