package main

import (
	"flag"
	"io"
	"log"
	"net/http"

	"github.com/gorilla/websocket"
)

var addr = flag.String("addr", "localhost:8080", "http service address")

var upgrader = websocket.Upgrader{
	WriteBufferSize: 253,
}

func ws(w http.ResponseWriter, r *http.Request) {
	i := 0
	c, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Print("upgrade:", err)
		return
	}
    buf := make([]byte, upgrader.WriteBufferSize)
	defer c.Close()
	for {
		mt, r, err := c.NextReader()
		if err != nil {
			log.Println("NextReader:", err)
			return
		}
		w, err := c.NextWriter(mt)
		if err != nil {
			log.Println("NextWriter:", err)
			return
		}
        n, err := io.CopyBuffer(w, r, buf)
		if err != nil {
			log.Println("Copy:", err)
			return
		}
		err = w.Close()
		if err != nil {
			log.Println("Close:", err)
			return
		}
		i++
		log.Printf("%p %d %d\n", c, i, n)
	}
}

func main() {
	flag.Parse()
	log.SetFlags(0)
	http.HandleFunc("/", ws)
	log.Printf("listen %s", *addr)
	log.Fatal(http.ListenAndServe(*addr, nil))
}
