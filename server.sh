#! /opt/homebrew/bin/bash

declare -A MIME_TYPES=(
  [html]="text/html"
  [htm]="text/html"
  [css]="text/css"
  [js]="application/javascript"
  [json]="application/json"
  [jpg]="image/jpeg"
  [jpeg]="image/jpeg"
  [png]="image/png"
  [gif]="image/gif"
  [svg]="image/svg+xml"
  [txt]="text/plain"
  [pdf]="application/pdf"
  [wasm]="application/wasm"
)

PORT=8080
ADDRESS='0.0.0.0'

fatal() {
    echo '[fatal]' "$@" >&2
    exit 1
}

html_encode() {
    local s=$1

    s=${s//&/\&amp;}
    s=${s//</\&lt;}
    s=${s//>/\&gt;}
    s=${s//\"/\&quot;}
    s=${s//\'/\&apos;}

    echo "$s"
}

list_directory() {
    local d="$1"

    #shopt -s nullglob dotglob

    echo '<h1>Directory Listing</h1>'
    echo "<h2>Directory: $(html_encode "$d")</h2>"
    echo '<hr>'
    echo '<ul>'

    for f in .. "$d"/*; do
        f=${f##*/}
        printf '<li><a href="%s">%s</a></li>' \
            "/$d/$(urlencode "$f")" \
            "$(html_encode "$f")"
    done
    echo '</ul>'
    echo '<hr>'
}

urldecode() {
    # Usage: urldecode "string"
    : "${1//+/ }"
    printf '%b\n' "${_//%/\\x}"
}

urlencode() {
    # Usage: urlencode "string"
    local LC_ALL=C
    for (( i = 0; i < ${#1}; i++ )); do
        : "${1:i:1}"
        case "$_" in
            [a-zA-Z0-9.~_-])
                printf '%s' "$_"
            ;;

            *)
                printf '%%%02X' "'$_"
            ;;
        esac
    done
    printf '\n'
}

parse_request() {
	declare -gA REQ_INFO=()
	declare -gA REQ_HEADERS=()

	local state='status'
	local line
	while read -r line; do
		line=${line%$'\r'}
		case "$state" in
			'status')
				local method path version
				read -r method path version <<< "$line"
				REQ_INFO[method]=$method
				REQ_INFO[path]=$path
				REQ_INFO[version]=$version
				state='headers'
				;;
			'headers')
				if [[ -z $line ]]; then
					break
				fi
				local key value
				IFS=: read -r key value <<< "$line"
				key=${key,,}
				value=${value# *}
				REQ_HEADERS[$key]=$value
				;;
			'body')
				fatal 'body parsing not supported'
				;;
		esac
	done
}

normalize_path() {
    local path=/$1
    
    IFS='/' read -r -a parts <<< "$path"
    local -a part
    local -a out=()

    for part in "${parts[@]}"; do
        case "$part" in
            '') ;;
            '.') ;;
            '..') unset 'out[-1]' 2>/dev/null;;
            *) out+=("$part");;
        esac
    done

    local s
    s=$(IFS=/; echo "${out[*]}")
    echo "/$s"
}

process_request() {
    
    local fd=$1
    parse_request <&"$fd"

	[[ ${REQ_INFO[version]} == 'HTTP/1.1' ]] || fatal 'unsupported HTTP verison'
	[[ ${REQ_INFO[method]} == 'GET' ]] || fatal 'unsupported HTTP verison'
	[[ ${REQ_INFO[path]} == /* ]] || fatal 'path must be absolute'

	echo "${REQ_INFO[method]} ${REQ_INFO[path]}"

    local path="${REQ_INFO[path]}"
    path=${path:1}
    
    local query
    IFS='?' read -r path query <<< "$path"

    path=$(urldecode "$path")
    path=$(normalize_path "$path")
    path=${path:1}
    path=${path:-'index.html'}

    local ext=${path#*.}
    ext=${ext,,}
    
    local ConType
    if [[ -n  "${MIME_TYPES[$ext]}" ]]; then
        ConType="${MIME_TYPES[$ext]}"
    else
        ConType='text/plain'
    fi

    if [[ -f $path ]]; then
        printf 'HTTP/1.1 200 OK\r\n' >&"$fd"
        printf "Content-Type: $ConType\r\n" >&"$fd"
        printf '\r\n' >&"$fd"
        cat "$path" >&"$fd"
    elif [[ -d $path ]]; then
        printf 'HTTP/1.1 200 OK\r\n' >&"$fd"
        printf 'Content-Type: text/html\r\n' >&"$fd"
        printf '\r\n' >&"$fd"
        list_directory "$path" >&"$fd"
    else
        printf 'HTTP/1.1 404 Not Found\r\n' >&"$fd"
        printf '\r\n' >&"$fd"
    fi

	exec {fd}>&-
}



main() {
	enable accept || fatal 'failed to load accept'

	echo "listening on http://$ADDRESS:$PORT"

	local fd ip
    while true; do
        accept -b "$ADDRESS" -v fd -r ip "$PORT" || fatal 'failed to read socket'
        process_request "$fd"
    done
}

main "$@"
