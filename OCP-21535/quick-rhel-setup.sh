#!/bin/bash

# 设置终端编码
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

printf "Quick RHEL Setup for AWS\n"
printf "========================\n\n"

printf "This script will help you quickly set up RHEL on AWS.\n\n"

# 检查当前订阅状态
printf "1. Checking current subscription status...\n"
subscription-manager status

printf "\n2. Checking if system is already registered...\n"
if subscription-manager identity >/dev/null 2>&1; then
    printf "System is already registered.\n"
    printf "Checking attached subscriptions...\n"
    subscription-manager list --consumed
else
    printf "System is not registered.\n"
    printf "You need to register with Red Hat to use dnf.\n\n"
    
    printf "Options for registration:\n"
    printf "A) Register with Red Hat account (username/password)\n"
    printf "B) Register with activation key\n"
    printf "C) Skip registration (dnf will not work)\n\n"
    
    read -p "Choose option (A/B/C): " reg_choice
    
    case $reg_choice in
        A|a)
            printf "\nRegistering with Red Hat account...\n"
            read -p "Enter your Red Hat username: " username
            subscription-manager register --username "$username"
            ;;
        B|b)
            printf "\nRegistering with activation key...\n"
            read -p "Enter your activation key: " activation_key
            read -p "Enter your organization ID: " org_id
            subscription-manager register --activationkey "$activation_key" --org "$org_id"
            ;;
        C|c)
            printf "\nSkipping registration. Note: dnf will not work without subscription.\n"
            ;;
        *)
            printf "Invalid choice. Exiting...\n"
            exit 1
            ;;
    esac
fi

# 如果注册成功，继续设置
if subscription-manager identity >/dev/null 2>&1; then
    printf "\n3. Attaching subscription...\n"
    subscription-manager attach --auto
    
    printf "\n4. Enabling repositories...\n"
    subscription-manager repos --enable=rhel-8-for-x86_64-baseos-rpms
    subscription-manager repos --enable=rhel-8-for-x86_64-appstream-rpms
    subscription-manager repos --enable=rhel-8-for-x86_64-supplementary-rpms
    
    printf "\n5. Updating system...\n"
    dnf update -y
    
    printf "\n6. Installing common tools...\n"
    dnf install -y vim wget curl git
    
    # Try to install htop from EPEL if available
    printf "Installing htop (if available)...\n"
    dnf install -y htop 2>/dev/null || printf "htop not available in default repositories\n"
    
    printf "\nSetup complete! You can now use dnf to install packages.\n"
else
    printf "\nSystem is not registered. You cannot use dnf without a subscription.\n"
    printf "To register later, use: subscription-manager register --username <your-username>\n"
fi

printf "\nUseful commands:\n"
printf "  - Check subscription: subscription-manager status\n"
printf "  - List available repos: subscription-manager repos --list\n"
printf "  - Install package: dnf install <package-name>\n"
printf "  - Search package: dnf search <package-name>\n"
