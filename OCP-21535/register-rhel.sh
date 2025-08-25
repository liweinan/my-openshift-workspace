#!/bin/bash

# 设置终端编码
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

printf "RHEL Subscription Registration Helper\n"
printf "=====================================\n\n"

printf "This script will help you register your RHEL instance with Red Hat.\n"
printf "You have several options:\n\n"

printf "1. Register with Red Hat account (recommended)\n"
printf "2. Register with activation key\n"
printf "3. Register with organization and activation key\n"
printf "4. Check current subscription status\n"
printf "5. Exit\n\n"

read -p "Choose an option (1-5): " choice

case $choice in
    1)
        printf "\nRegistering with Red Hat account...\n"
        printf "You will need your Red Hat username and password.\n\n"
        read -p "Enter your Red Hat username: " username
        printf "Password will be prompted securely...\n"
        subscription-manager register --username "$username"
        ;;
    2)
        printf "\nRegistering with activation key...\n"
        printf "You will need your activation key and organization ID.\n\n"
        read -p "Enter your activation key: " activation_key
        read -p "Enter your organization ID: " org_id
        subscription-manager register --activationkey "$activation_key" --org "$org_id"
        ;;
    3)
        printf "\nRegistering with organization and activation key...\n"
        read -p "Enter your organization ID: " org_id
        read -p "Enter your activation key: " activation_key
        subscription-manager register --org "$org_id" --activationkey "$activation_key"
        ;;
    4)
        printf "\nChecking current subscription status...\n"
        subscription-manager status
        printf "\nChecking available subscriptions...\n"
        subscription-manager list --available
        ;;
    5)
        printf "Exiting...\n"
        exit 0
        ;;
    *)
        printf "Invalid option. Please run the script again.\n"
        exit 1
        ;;
esac

printf "\nAfter registration, you may need to:\n"
printf "1. Attach a subscription: subscription-manager attach --auto\n"
printf "2. Enable repositories: subscription-manager repos --enable=rhel-8-for-x86_64-baseos-rpms\n"
printf "3. Update system: dnf update -y\n\n"

printf "Common repositories to enable:\n"
printf "- rhel-8-for-x86_64-baseos-rpms\n"
printf "- rhel-8-for-x86_64-appstream-rpms\n"
printf "- rhel-8-for-x86_64-supplementary-rpms\n"
