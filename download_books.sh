#!/bin/bash

mkdir -p books

echo "Downloading Moby Dick..."
curl -s -L --retry 3 -o "books/moby_dick.txt" "https://www.gutenberg.org/files/2701/2701-0.txt" && echo "  done" || echo "  FAILED"

echo "Downloading Frankenstein..."
curl -s -L --retry 3 -o "books/frankenstein.txt" "https://www.gutenberg.org/files/84/84-0.txt" && echo "  done" || echo "  FAILED"

echo "Downloading Pride and Prejudice..."
curl -s -L --retry 3 -o "books/pride_and_prejudice.txt" "https://www.gutenberg.org/files/1342/1342-0.txt" && echo "  done" || echo "  FAILED"

echo "Downloading Dracula..."
curl -s -L --retry 3 -o "books/dracula.txt" "https://www.gutenberg.org/files/345/345-0.txt" && echo "  done" || echo "  FAILED"

echo "Downloading The Odyssey..."
curl -s -L --retry 3 -o "books/the_odyssey.txt" "https://www.gutenberg.org/files/1727/1727-0.txt" && echo "  done" || echo "  FAILED"

echo ""
echo "Books in ./books/:"
ls -lh books/
