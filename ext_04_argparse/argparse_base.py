import argparse

# Создаём парсер
parser = argparse.ArgumentParser(description='Пример программы')

# Добавляем аргументы
parser.add_argument('filename', help='Имя файла')  # Позиционный аргумент
parser.add_argument('-v', '--verbose', action='store_true', help='Включить подробный вывод')  # Флаг
parser.add_argument('--count', type=int, default=1, help='Количество повторений')  # Опция с значением

# Парсим аргументы
args = parser.parse_args()

# Используем в коде
print(f"Файл: {args.filename}, Count: {args.count}, Verbose: {args.verbose}")
