#!/bin/bash


# Глобальные переменные
gREPORT_DIR="$(mktemp -d -p /tmp/ email_verify_XXXXXXXXX)"
gMX_BAD="$gREPORT_DIR/mx_bad.txt"
gEMAILS_BAD="$gREPORT_DIR/emails_bad.txt"
gEMAILS_GOOD="$gREPORT_DIR/emails_good.txt"

# Хук для аварийного выхода
trap "_exit" INT KILL TERM QUIT
_exit() {
	exit $1
}

# Установлен ли expect
which expect &>/dev/null
if [ "$?" -ne 0 ]
	then
		echo -e "Check expect: \t\t\t\t\t\t[ FAIL ]"
		echo -e "Please install expect!!!"
		exit 200
fi

# Установлен ли netcat
which nc &>/dev/null
if [ "$?" -ne 0 ]
	then
		echo -e "Check nc: \t\t\t\t\t\t[ FAIL ]"
		echo -e "Please install nc!!!"
		exit 200
fi

# Проверка аргументов
if [ $# -ne 1 ] ; then
	echo "Usage: $0 /path/to/emails_list"
	exit 250
fi
gEMAILS_LIST="${1}"

# Проверка MX сереров по списку email'ов
grep -Ev '^$' "$gEMAILS_LIST" | sed -e 's/^\s\+//g;s/\s\+$//g;s/\.$//g;s/;$//g' | while read wEMAIL ; do
	# Если во время пред. проверки все MX не ответили на "стук" в 25 порт,
	# то записать этот email как "плохой"
	if [ ${#wEMAIL_MX_BAD} -gt 0 ] ; then 
		echo ${wEMAIL_MX_BAD} >> $gMX_BAD
		echo -e "*BAD\t\t$wEMAIL_MX_BAD"
	fi
	wEMAIL_MX_BAD=''
	wDOMAIN="$(echo "$wEMAIL" | awk -F'@' '{print $2}')"
	wMX=''
	# есть у сервера MX ?
	wMX="$(host -t mx "$wDOMAIN" | awk '{print $7}' | sed 's/\.$//')"
	if [ ${#wMX} -gt 0 ] ; then
		# проверяем все по порядку, на случай если есть "мертвый" MX
		# после первой успешной проверки останавливаемся
		echo "${wMX}" | while read wMX_CURRENT ; do
			nc -zw 3 $wMX_CURRENT 25 &>/dev/null
			if [ $? -eq 0 ] ; then
				sleep 1s
				# MX рабочий, проверяем мыло
				wTMP_USER="$(head /dev/urandom | tr -dc 'a-z' | fold -w 6 | head -n 1)"
				wTMP_DOMAIN="$(head /dev/urandom | tr -dc 'a-z' | fold -w 6 | head -n 1).com"
				wTMP_FROM="$wTMP_USER@$wTMP_DOMAIN"
				echo '' > $gREPORT_DIR/email_verify.expect
				echo '' > $gREPORT_DIR/email_verify.expect.result

# Генерируем expect скрипт для текущего email'а
cat << __EOF > $gREPORT_DIR/email_verify.expect
#!/bin/expect
spawn nc $wMX_CURRENT 25
expect "ESMTP"
send "HELO $wTMP_DOMAIN\r"
expect "service"
send "MAIL FROM: <$wTMP_FROM>\r"
expect "OK"
send "RCPT TO: <$wEMAIL>\r"
expect "OK"
send "quit\r"
expect eof
__EOF

				# проверяем
				expect $gREPORT_DIR/email_verify.expect &>$gREPORT_DIR/email_verify.expect.result
				grep -sq "550" $gREPORT_DIR/email_verify.expect.result
				if [ $? -eq 0 ] ; then
					# нет такого мыла
					echo "$wEMAIL" >> $gEMAILS_BAD
					echo -e "*BAD\t\t$wEMAIL"
				else
					# мыло есть
					echo "$wEMAIL" >> $gEMAILS_GOOD
					echo -e "GOOD\t\t$wEMAIL"
				fi
				# Очищаем переменную, чтобы текущий email не попал в "плохие"
				wEMAIL_MX_BAD=''
				break
			else
				# 25 порт на текущем проверяемом MX закрыт, заносим email в "возможно плохой"
				wEMAIL_MX_BAD="${wEMAIL}"
			fi
		done
	else
		# У сервера нет MX, считаем этот email "плохим"
		echo ${wEMAIL} >> $gMX_BAD
		echo -e "*BAD\t\t$wEMAIL"
	fi
done
echo "See report in $gREPORT_DIR"

_exit 0
