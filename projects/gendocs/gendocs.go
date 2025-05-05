package main

import (
	"flag"

	v1 "github.com/galleybytes/tf3/pkg/apis/tf3/v1"
)

var (
	templatefile string
	outputfile   string
)

func init() {
	flag.StringVar(&templatefile, "tpl", "", "Path to the template")
	flag.StringVar(&outputfile, "out", "", "Path to save rendered template")
	flag.Parse()
}

func main() {
	v1.Generate(templatefile, outputfile)
}
