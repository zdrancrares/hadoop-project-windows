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

echo "Downloading War and Peace..."
curl -s -L --retry 3 -o "books/war_and_peace.txt" "https://www.gutenberg.org/files/2600/2600-0.txt" && echo "  done" || echo "  FAILED"

echo "Downloading The Adventures of Sherlock Holmes..."
curl -s -L --retry 3 -o "books/sherlock_holmes.txt" "https://www.gutenberg.org/files/1661/1661-0.txt" && echo "  done" || echo "  FAILED"

echo "Downloading Alice's Adventures in Wonderland..."
curl -s -L --retry 3 -o "books/alice_in_wonderland.txt" "https://www.gutenberg.org/files/11/11-0.txt" && echo "  done" || echo "  FAILED"

echo "Downloading A Tale of Two Cities..."
curl -s -L --retry 3 -o "books/tale_of_two_cities.txt" "https://www.gutenberg.org/files/98/98-0.txt" && echo "  done" || echo "  FAILED"

echo "Downloading The Picture of Dorian Gray..."
curl -s -L --retry 3 -o "books/dorian_gray.txt" "https://www.gutenberg.org/files/174/174-0.txt" && echo "  done" || echo "  FAILED"

echo "Downloading Crime and Punishment..."
curl -s -L --retry 3 -o "books/crime_and_punishment.txt" "https://www.gutenberg.org/files/2554/2554-0.txt" && echo "  done" || echo "  FAILED"

echo "Downloading Anna Karenina..."
curl -s -L --retry 3 -o "books/anna_karenina.txt" "https://www.gutenberg.org/files/1399/1399-0.txt" && echo "  done" || echo "  FAILED"

echo "Downloading Romeo and Juliet..."
curl -s -L --retry 3 -o "books/romeo_and_juliet.txt" "https://www.gutenberg.org/files/1513/1513-0.txt" && echo "  done" || echo "  FAILED"

echo "Downloading The Count of Monte Cristo..."
curl -s -L --retry 3 -o "books/monte_cristo.txt" "https://www.gutenberg.org/files/1184/1184-0.txt" && echo "  done" || echo "  FAILED"

echo "Downloading Don Quixote..."
curl -s -L --retry 3 -o "books/don_quixote.txt" "https://www.gutenberg.org/files/996/996-0.txt" && echo "  done" || echo "  FAILED"

echo ""
echo "Books in ./books/:"
ls -lh books/