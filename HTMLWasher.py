#!/usr/local/bin/python3
#coding=utf8

import re
import sys
from html.parser import HTMLParser

ownName='Michael'

class Anonymizer:
    id=1
    anom={}
    publicTexts=[
        '/gp/product/',
        '/order-details/',
        '/myapps/',
        '/order-history/',
        'orderID=',
        'orderId=',
        '/gp/digital/',
        'https://www.amazon.de/dp/',
        '/gp/css/order-history',
        
    ]

    searchStrings={
        'P':'\d+,\d\d',
        'D':'\d+\. [a-zA-Zä]+ \d{4}',
        'O':'[D\d]\d{2}\-\d{7}-\d{7}',
        'N':ownName
    }
    
    p=re.compile('^(.*?)('+'|'.join(list(searchStrings.values())+publicTexts)+')(.*?)$')
    

    def __init__(self,text,clear=False):
        prefix="T"
        for k in Anonymizer.searchStrings.keys():
            if re.search(Anonymizer.searchStrings[k], text):
                prefix=k
        self.tag='_'+prefix+str(Anonymizer.id)+'_'
        #print(self.tag+"='"+text+"'")
        Anonymizer.id=Anonymizer.id+1
        #self.text=text
        if clear==True:
            self.tag=text
            Anonymizer.anom[text]=self
    
    @classmethod
    def do(cls,text):
        
        if text =='':
            return ''
        res=[]
        while True:
            m=cls.p.match(text)
            if m:
                res.append(cls.get(m.group(1)))
                res.append(cls.get(m.group(2)))
                #print(text, m.groups())
                text=m.group(3)
            else:
                break
        res.append(cls.get(text))
        return ''.join(res)
        
    @classmethod
    def get(cls,text):
        if text == '':
            return ''
        if text in cls.publicTexts:
            return text
        if text in cls.anom:
            return cls.anom[text].tag

        cls.anom[text]=cls(text)
        return cls.anom[text].tag 

class MyHTMLParser(HTMLParser):
    wantedAttr=('class','type','id','name','href','charset')
    filterTags=('script','style') #
    
    def __init__(self):
        self.text=[]
        self.record=True
        HTMLParser.__init__(self)
    def handle_starttag(self, tag, attrs):
        if tag in self.filterTags:
            self.record=False
            return
        nAttrs=[tag]
        for a in attrs:
            val=a[1]
            if a[0] in MyHTMLParser.wantedAttr:
                if a[0] == 'href':
                    val=Anonymizer.do(val)
                nAttrs.append(a[0]+'="'+val+'"')
        self.text.append('<'+' '.join(nAttrs)+'>')
            

    def handle_endtag(self, tag):
        if tag in MyHTMLParser.filterTags:
            self.record=True
            return
        self.text.append('</'+tag+'>')

    def handle_data(self, data):
        if self.record:
            self.text.append(Anonymizer.do(data.lstrip().rstrip()))
    
    def show(self):
        print(''.join(self.text))
    
    def write(self):
        with open("public_page.html","w") as f:
            print("write public_page.html")
            f.write(''.join(self.text))

        with open("secret_page.txt","w") as f:
            print("write secret_page.txt")
            for k in Anonymizer.anom:
                f.write(Anonymizer.anom[k].tag+"='"+k+"'\n")
            

if __name__ == '__main__':
    if len(sys.argv)>1:
        with open(sys.argv[1]) as f:
            t=f.read()
    else:
        t=sys.stdin.read()
    
    t=re.sub('\s'," ",t)

    
    
    parser = MyHTMLParser()
    parser.feed(t)
    
    parser.write()
    
    
