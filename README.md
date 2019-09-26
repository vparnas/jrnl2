# jrnl2

## Description 

A plain text, CLI journaling system inspired by [jrnl.sh](http://jrnl.sh/usage.html), differences being:

1. Speed. Executes much faster, notable especially on older hardware. Built in shell script, not python. Leverages sed/grep for most read/write operations. 
1. Similar CLI interface, but with some differences and only (what I deemed as) the most important features. 
1. Doesn't segregate the search space. Search for tags, time-frame, or regular text across the entire records. 
1. Additional time-tracking/reporting module `jrnl-time`.

## Features

- Create new journal entries via a text buffer, standard input, or the command line.
- Entries acquire the current time stamp by default, or a custom time stamp if specified.
- Designate tags with a '@' prefix for special coloring in the search output.
- Search existing entries for tags, a date range, or regular text, via regular expressions. 
- Combine multiple search patterns conjunctively or disjunctively.
- Limit the search output to a specified number of entries.
- Return full entries or merely the headers in searches.
- Display only the tags contained in the search space.
- Edit/delete existing entries.
- Supports multiple journals.
- Create time-start and time-end markers for specific or generic tasks, in the default or separate journal. 
- Report on all relevant (search filterable) time-tracking related tasks.

## Non-features

- Encryption. As all journals comprise of plain text, you can interface a journal with `gpg/pgp` (or your preferred framework) without much difficulty .
- Special syntax for date searches in human language. I find this nice, but not too critical in most cases, although I may add more elaborate date searches in the future. As of now, all timestamps respect the `%Y-%m-%d %H:%M` format by default (configurable). As such, you can exercise some craftiness and search for something like `-s '2019-09'` to return all September 2019 entries, or `-s '2019-0[\^1-5]'` to return everything from June 2019 and onwards (not to mention that you can combine searches).
- Export/import to/from different formats. Again, plain text. Converting or parsing your output shouldn't be too difficult via the standard available Unix tools.

## Requirements

Optional, for `jrnl-time`: 

    - `dmenu` or `slmenu`
    - `notify-send`

## Usage

### jrnl2

Display command line help:

```
jrnl -h
```

Ways to create a new entry:

```
jrnl "This is a new entry"
echo "This is another entry with a @tag" | jrnl    
cat typed-entry.txt > jrnl
# The following will open a text buffer to edit your new entry
jrnl
jrnl "Repeating the @tag a second time"
```

Display the last four entries

```
jrnl -n 4
2019-09-26 15:11 This is a new entry

2019-09-26 15:11 This is another entry with a @tag

2019-09-26 15:12 Another entry that I typed in VIM containing yet @anothertag.

Additional text.
And more with @thirdtag
And more yet.

2019-09-26 15:16 Repeating the @tag a second time
```

Display the headers only:

```
jrnl -n 4 --short
2019-09-26 15:11 This is a new entry
2019-09-26 15:11 This is another entry with a @tag
2019-09-26 15:12 Another entry containing yet @anothertag.
2019-09-26 15:16 Repeating the @tag a second time
```

Display tags contained in the entire journal, along with their respective count:

```
jrnl --tags
2 @tag
1 @thirdtag
1 @anothertag
```

Search for cases of a specific tag:

```
jrnl -s @tag --short
2019-09-26 15:11 This is another entry with a @tag
2019-09-26 15:16 Repeating the @tag a second time
```

(Case insensitive) search for entries containing both 'entry' and 'another'

```
jrnl -s entry -s another

2019-09-26 15:11 This is another entry with a @tag

2019-09-26 15:12 Another entry containing yet @anothertag.

Some more lines.
Some more lines. @thirdtag
Some more lines.
```

Display only the tags contained within those entries:

```
jrnl -s entry -s another --tags
1 @thirdtag
1 @tag
1 @anothertag
```

Edit/delete those same entries:

```
jrnl -s entry -s another --edit
```

### jrnl-time

Command line options:

```
jrnl-time -h
jrnl-time:
    -h: help text,
    -s: start timetracking a task
    -e: end timetracking
    -r: report on all timetracking
```

Usage:

```
jrnl-time -s @newtask
1 new entry written
Tracking time for @time-track @newtask

jrnl-time -s @newtask
Time already running

jrnl-time -e
1 new entry written
End time for @time-track @newtask

jrnl-time -e
No time currently tracked
```

Display the time-tracking tasks in the 'time-track' journal:

```
jrnl time-track --short
2019-09-26 15:26 @time-track @newtask start
2019-09-26 15:45 @time-track @newtask end
```

Time reporting. Everything after '-r' gets passed verbatim into jrnl.

```
jrnl-time -r # Or jrnl-time -r -n 2
Can pass additional *conjunctive* search terms or restrictive options to jrnl in quotes.

@time-track: 0d 0h 19m
@newtask: 0d 0h 19m
```


## Configuration

Include `~/.jrnl2.rc` in your home directory to overwrite the default configuration values:

```conf
TIME_TRACK_TAG="@time-track"
TIME_TRACK_JOURNAL="time-track"
TAG_COLOR="00;36" 

TIMEFORMAT="%Y-%m-%d %H:%M"
RECORD_START_PAT="[0-9]{4}-[0-9]{2}-[0-9]{2}\s[0-9]{2}:[0-9]{2}"
EDITOR="vim"

declare -A JOURNALS=(
    ['default']="$HOME/journals/journal.txt" 
    ['time-track']="$HOME/journals/time-track.txt"
)
```
