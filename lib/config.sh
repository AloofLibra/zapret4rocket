#!/bin/sh

config_get_file() {
  if [ -n "$1" ] && [ -f "$1" ]; then
    echo "$1"
    return 0
  fi
  if [ -f /opt/zapret2/config ]; then
    echo /opt/zapret2/config
    return 0
  fi
  if [ -f /opt/zapret2/config.default ]; then
    echo /opt/zapret2/config.default
    return 0
  fi
  return 1
}

get_config_file() {
  config_get_file "$@"
}

config_var_exists() {
  local cfg="$1"
  local var="$2"
  [ -f "$cfg" ] || return 1
  grep -q "^${var}=" "$cfg"
}

config_get_var() {
  local cfg="$1"
  local var="$2"
  [ -z "$cfg" ] && cfg="$(config_get_file)" || true
  [ -f "$cfg" ] || return 1
  sed -n "s/^${var}=//p" "$cfg" | head -n1
}

config_set_var() {
  local cfg="$1"
  local var="$2"
  local val="$3"
  local esc_val

  [ -f "$cfg" ] || return 1
  esc_val=$(printf '%s' "$val" | sed 's/[\/&]/\\&/g')
  if grep -q "^${var}=" "$cfg"; then
    sed -i "s#^${var}=.*#${var}=${esc_val}#" "$cfg"
  else
    printf '%s=%s\n' "$var" "$val" >> "$cfg"
  fi
}

config_hostlist_mode_text() {
  local cfg
  cfg="$(config_get_file "$1")" || { echo "неизвестно"; return 0; }
  if grep -q '^MODE_FILTER=autohostlist' "$cfg"; then
    echo "авто"
  elif grep -q '^MODE_FILTER=hostlist' "$cfg"; then
    echo "по листам"
  else
    echo "неизвестно"
  fi
}

config_tls_blob_mode_text() {
  local cfg
  local has_tls_maxru=0
  local has_tls_default=0
  cfg="$(config_get_file "$1")" || { echo "не определён"; return 0; }

  if awk '
      /--lua-desync=/ && /blob=maxru/ && $0 !~ /strategy=26/ {found=1}
      END {exit(found?0:1)}
    ' "$cfg"; then
    has_tls_maxru=1
  fi
  if awk '
      /--lua-desync=/ && /blob=fake_default_tls/ && $0 !~ /strategy=26/ {found=1}
      END {exit(found?0:1)}
    ' "$cfg"; then
    has_tls_default=1
  fi

  if [ "$has_tls_maxru" -eq 1 ] && [ "$has_tls_default" -eq 0 ]; then
    echo "maxru"
  elif [ "$has_tls_default" -eq 1 ] && [ "$has_tls_maxru" -eq 0 ]; then
    echo "fake_default_tls"
  elif [ "$has_tls_default" -eq 1 ] && [ "$has_tls_maxru" -eq 1 ]; then
    echo "mixed"
  else
    echo "не определён"
  fi
}

config_tls_blob_text() {
  local cfg blob_file mode
  cfg="$(config_get_file "$1")" || { echo "неизвестно"; return 0; }
  mode="$(config_tls_blob_mode_text "$cfg")"
  case "$mode" in
    fake_default_tls) echo "default"; return ;;
    mixed) echo "mixed"; return ;;
  esac
  blob_file="$(sed -n -E 's#.*--blob=maxru:@/opt/zapret2/files/fake/([^[:space:]]+).*#\1#p' "$cfg" | head -n1)"
  [ -n "$blob_file" ] && echo "$blob_file" || echo "неизвестно"
}

config_profile_max_strategy() {
  local profile="$1"
  local cfg
  cfg="$(config_get_file "$2")" || { echo 0; return 0; }

  if [ "$profile" = "8" ] || [ "$profile" = "9" ]; then
    local begin_marker end_marker fallback_max
    if [ "$profile" = "9" ]; then
      begin_marker="#Z2R_FALLBACK_HTTP_BEGIN"
      end_marker="#Z2R_FALLBACK_HTTP_END"
    else
      begin_marker="#Z2R_FALLBACK_BEGIN"
      end_marker="#Z2R_FALLBACK_END"
    fi
    fallback_max="$(awk -v begin="$begin_marker" -v end="$end_marker" '
        function scan_strategies(line) {
            while (match(line, /strategy=[0-9]+/)) {
                num=substr(line, RSTART+9, RLENGTH-9)+0
                if (in_template && num>tplmax[tpl]) tplmax[tpl]=num
                if (inblk && num>max) max=num
                line=substr(line, RSTART+RLENGTH)
            }
        }
        BEGIN{inblk=0; in_template=0; tpl=""; max=0}
        /^--template=/ {
            in_template=1
            tpl=$0
            sub(/^--template=/, "", tpl)
            sub(/[[:space:]].*$/, "", tpl)
        }
        /^[[:space:]]*--new[[:space:]]*$/ {in_template=0; tpl=""}
        index($0, begin) {inblk=1; next}
        index($0, end) {inblk=0; exit}
        inblk {
            if ($0 ~ /^--import([=[:space:]]|$)/) {
                imp=$0
                sub(/^--import[=[:space:]]+/, "", imp)
                sub(/[[:space:]].*$/, "", imp)
                if (tplmax[imp]>max) max=tplmax[imp]
            }
        }
        { scan_strategies($0) }
        END{print max}
    ' "$cfg")"
    if [ -n "$fallback_max" ] && [ "$fallback_max" -gt 0 ]; then
      echo "$fallback_max"
      return 0
    fi
  fi

  awk -v pid="$profile" '
      function scan_strategies(line) {
          while (match(line, /strategy=[0-9]+/)) {
              num=substr(line, RSTART+9, RLENGTH-9)+0
              if (in_template && num>tplmax[tpl]) tplmax[tpl]=num
              if (!in_template && active && prof==pid && num>max) max=num
              line=substr(line, RSTART+RLENGTH)
          }
      }
      function start_profile_if_needed() {
          if (!in_template && !active && $0 ~ /^--/ && $0 !~ /^--new/ && $0 !~ /^--lua-init/ && $0 !~ /^--blob=/) {
              prof++
              active=1
          }
      }
      BEGIN{inopt=0; prof=0; active=0; in_template=0; tpl=""; max=0}
      /^NFQWS2_OPT="/ {inopt=1}
      inopt {
          if ($0 ~ /^--template=/) {
              in_template=1
              tpl=$0
              sub(/^--template=/, "", tpl)
              sub(/[[:space:]].*$/, "", tpl)
          } else {
              start_profile_if_needed()
          }
          if (!in_template && active && prof==pid && $0 ~ /^--import([=[:space:]]|$)/) {
              imp=$0
              sub(/^--import[=[:space:]]+/, "", imp)
              sub(/[[:space:]].*$/, "", imp)
              if (tplmax[imp]>max) max=tplmax[imp]
          }
          scan_strategies($0)
          if ($0 ~ /^--new/) {active=0; in_template=0; tpl=""}
          if ($0 ~ /^"$/) exit
      }
      END{print max}
  ' "$cfg"
}

config_tcp443_current_strategy() {
  local cfg
  cfg="$(config_get_file "$1")" || { echo 0; return 0; }
  awk '
    /^[[:space:]]*#Z2R_TCP443_BEGIN$/ {inblk=1; next}
    /^[[:space:]]*#Z2R_TCP443_END$/ {inblk=0; exit}
    inblk && $0 ~ /^--filter-tcp=443 --hostlist-domains=/ {
      n++
      if ($0 ~ /^--filter-tcp=443 --hostlist-domains= --/) {print n; found=1; exit}
    }
    END{if (!found) print 0}
  ' "$cfg"
}

config_tcp443_set_strategy() {
  local strategy="$1"
  local cfg
  cfg="$(config_get_file "$2")" || return 1
  awk -v target="$strategy" '
    /^[[:space:]]*#Z2R_TCP443_BEGIN$/ {inblk=1; print; next}
    /^[[:space:]]*#Z2R_TCP443_END$/ {inblk=0; print; next}
    inblk && $0 ~ /^--filter-tcp=443 --hostlist-domains=/ {
      count++
      sub(/--hostlist-domains= --/, "--hostlist-domains=none.dom --")
      if (target > 0 && count == target) {
        sub(/--hostlist-domains=none\.dom --/, "--hostlist-domains= --")
        changed=1
      }
    }
    {print}
    END{exit((target==0 || changed)?0:1)}
  ' "$cfg" > "${cfg}.tmp" && mv "${cfg}.tmp" "$cfg"
}
